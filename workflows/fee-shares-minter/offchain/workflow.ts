import {
  bytesToHex,
  cre,
  encodeCallMsg,
  getNetwork,
  handler,
  type Runtime,
} from '@chainlink/cre-sdk';
import {
  decodeEventLog,
  decodeFunctionResult,
  encodeAbiParameters,
  encodeFunctionData,
  parseAbiParameters,
  zeroAddress,
  type Hex,
} from 'viem';
import {shouldSubmit, submitReport} from '../../shared/offchain/checkUpkeep';
import {IHubABI} from '../../shared/offchain/abi/IHub';
import {type Config, type NetworkConfig, type Target, configSchema} from './types';

export {configSchema};

type EvmClient = InstanceType<typeof cre.capabilities.EVMClient>;

type MintFeeSharesArgs = {
  assetId: bigint;
  feeReceiver: Hex;
  shares: bigint;
  assets: bigint;
};

type TargetResult = {minted: number; skipped: number; assetCount: bigint};

function encodeCheckData(hub: string, assetId: bigint): Hex {
  return encodeAbiParameters(parseAbiParameters('address hub, uint256 assetId'), [
    hub as Hex,
    assetId,
  ]);
}

function readAssetCount(
  runtime: Runtime<Config>,
  evmClient: EvmClient,
  hub: string,
): bigint {
  const calldata = encodeFunctionData({abi: IHubABI, functionName: 'getAssetCount', args: []});
  const reply = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({from: zeroAddress, to: hub as Hex, data: calldata}),
    })
    .result();
  return decodeFunctionResult({
    abi: IHubABI,
    functionName: 'getAssetCount',
    data: bytesToHex(reply.data),
  }) as bigint;
}

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

export function runForTarget(
  runtime: Runtime<Config>,
  evmClient: EvmClient,
  network: NetworkConfig,
  target: Target,
): TargetResult {
  const label = `${network.chainName}:${target.hub}`;
  runtime.log(`[${label}] tick (minter=${target.minter})`);

  const assetCount = readAssetCount(runtime, evmClient, target.hub);
  runtime.log(`[${label}] assetCount=${assetCount}`);

  let minted = 0;
  let skipped = 0;
  for (let assetId = 0n; assetId < assetCount; assetId++) {
    const sublabel = `${label}:asset=${assetId}`;
    const checkData = encodeCheckData(target.hub, assetId);
    const performData = shouldSubmit(runtime, evmClient, target.minter, checkData, sublabel);
    if (!performData) {
      skipped++;
      continue;
    }

    const txHash = submitReport(runtime, evmClient, target.minter, performData, sublabel);
    if (!txHash) {
      skipped++;
      continue;
    }

    const event = findMintFeeSharesEvent(runtime, evmClient, txHash, target.hub);
    if (event) {
      runtime.log(
        `[${sublabel}] MintFeeShares` +
          ` | feeReceiver=${event.args.feeReceiver}` +
          ` | shares=${event.args.shares}` +
          ` | assets=${event.args.assets}` +
          ` | tx=${txHash}`,
      );
    } else {
      runtime.log(`[${sublabel}] tx ${txHash} succeeded but no MintFeeShares event found`);
    }
    minted++;
  }

  return {minted, skipped, assetCount};
}

export const createTargetHandler = (network: NetworkConfig, target: Target) => {
  return (runtime: Runtime<Config>): string => {
    const label = `${network.chainName}:${target.hub}`;
    const cre_network = getNetwork({
      chainFamily: 'evm',
      chainSelectorName: network.chainName,
      isTestnet: network.isTestnet,
    });
    if (!cre_network) {
      runtime.log(`[${label}] network not found — skipping`);
      return 'Network not found';
    }
    const evmClient = new cre.capabilities.EVMClient(cre_network.chainSelector.selector);

    try {
      const res = runForTarget(runtime, evmClient, network, target);
      return `evaluated ${res.assetCount} assets, minted ${res.minted}, skipped ${res.skipped}`;
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
        .map((t) => handler(trigger, createTargetHandler(net, t))),
    );
};
