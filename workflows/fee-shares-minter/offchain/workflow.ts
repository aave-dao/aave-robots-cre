import {bytesToHex, cre, getNetwork, handler, type Runtime} from '@chainlink/cre-sdk';
import {decodeEventLog, encodeAbiParameters, parseAbiParameters, type Hex} from 'viem';
import {shouldSubmit, submitReport} from '../../shared/offchain/checkUpkeep';
import {IHubABI} from '../../shared/offchain/abi/IHub';
import {type Config, type Target, configSchema} from './types';

export {configSchema};

type EvmClient = InstanceType<typeof cre.capabilities.EVMClient>;

type MintFeeSharesArgs = {
  assetId: bigint;
  feeReceiver: Hex;
  shares: bigint;
  assets: bigint;
};

const encodeCheckData = (target: Target): Hex =>
  encodeAbiParameters(parseAbiParameters('address hub, uint256 assetId'), [
    target.hub as Hex,
    BigInt(target.assetId),
  ]);

function findMintFeeSharesEvent(
  runtime: Runtime<Config>,
  evmClient: EvmClient,
  txHash: string,
  hub: string,
): {hub: Hex; args: MintFeeSharesArgs} | null {
  const {receipt} = evmClient.getTransactionReceipt(runtime, {hash: txHash}).result();
  if (!receipt) return null;

  const hubLower = hub.toLowerCase();
  for (const log of receipt.logs) {
    const logAddr = bytesToHex(log.address).toLowerCase();
    if (logAddr !== hubLower) continue;
    try {
      const decoded = decodeEventLog({
        abi: IHubABI,
        topics: log.topics.map((t) => bytesToHex(t)) as [Hex, ...Hex[]],
        data: bytesToHex(log.data),
      });
      if (decoded.eventName === 'MintFeeShares') {
        return {hub: logAddr as Hex, args: decoded.args as unknown as MintFeeSharesArgs};
      }
    } catch {
      // log doesn't match any event in IHubABI — skip
    }
  }
  return null;
}

export const createTargetHandler = (chainName: string, target: Target) => {
  return (runtime: Runtime<Config>): string => {
    const label = `${chainName}:${target.minter}:asset=${target.assetId}`;
    runtime.log(`[${label}] tick`);

    const network = getNetwork({
      chainFamily: 'evm',
      chainSelectorName: chainName,
      isTestnet: false,
    });
    if (!network) {
      runtime.log(`[${label}] network not found — skipping`);
      return 'Network not found';
    }
    const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector);

    try {
      const performData = shouldSubmit(
        runtime,
        evmClient,
        target.minter,
        encodeCheckData(target),
        label,
      );
      if (!performData) return 'No upkeep needed';

      const txHash = submitReport(runtime, evmClient, target.minter, performData, label);
      if (!txHash) return 'Submission skipped';

      const event = findMintFeeSharesEvent(runtime, evmClient, txHash, target.hub);
      if (!event) {
        runtime.log(`[${label}] tx ${txHash} succeeded but no MintFeeShares event found`);
        return txHash;
      }

      runtime.log(
        `[${label}] MintFeeShares` +
          ` | hub=${event.hub}` +
          ` | assetId=${event.args.assetId}` +
          ` | feeReceiver=${event.args.feeReceiver}` +
          ` | shares=${event.args.shares}` +
          ` | assets=${event.args.assets}` +
          ` | tx=${txHash}`,
      );
      return txHash;
    } catch (e) {
      runtime.log(`[${label}] failed: ${e}`);
      return 'Processing failed';
    }
  };
};

export const initWorkflow = (config: Config) => {
  const trigger = new cre.capabilities.CronCapability().trigger({schedule: config.schedule});

  return config.evms
    .filter((net) => net.chainName && net.targets.length > 0)
    .flatMap((net) =>
      net.targets
        .filter((t) => t.minter && t.hub)
        .map((t) => handler(trigger, createTargetHandler(net.chainName, t))),
    );
};
