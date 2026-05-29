import {describe, expect} from 'bun:test';
import {TxStatus, getNetwork} from '@chainlink/cre-sdk';
import {EvmMock, newTestRuntime, test} from '@chainlink/cre-sdk/test';
import {
  encodeAbiParameters,
  encodeEventTopics,
  hexToBytes,
  parseAbiParameters,
  type Hex,
} from 'viem';

import {IHubABI} from '../../shared/offchain/abi/IHub';
import {dispatchCallContract, mockLog, mockReceipt} from '../../shared/offchain/testing/mocks';
import {createTargetHandler} from './workflow';

const CHAIN_NAME = 'ethereum-mainnet';
const CHAIN_SELECTOR = getNetwork({
  chainFamily: 'evm',
  chainSelectorName: CHAIN_NAME,
  isTestnet: false,
})!.chainSelector.selector;

const MINTER = '0x1111111111111111111111111111111111111111' as Hex;
const HUB = '0x2222222222222222222222222222222222222222' as Hex;
const FEE_RECEIVER = '0x3333333333333333333333333333333333333333' as Hex;
const TX_HASH = ('0xab' + 'cd'.repeat(31)) as Hex;

const TARGET = {minter: MINTER, hub: HUB};
const NETWORK = {chainName: CHAIN_NAME, isTestnet: false, targets: [TARGET]};
const CONFIG = {schedule: '* * * * *', evms: [NETWORK]};

function makeRuntime() {
  const runtime = newTestRuntime();
  (runtime as unknown as {config: typeof CONFIG}).config = CONFIG;
  return runtime;
}

function mintFeeSharesLog(assetId: bigint, shares: bigint, assets: bigint) {
  const topics = encodeEventTopics({
    abi: IHubABI,
    eventName: 'MintFeeShares',
    args: {assetId, feeReceiver: FEE_RECEIVER},
  }) as readonly Hex[];
  const data = encodeAbiParameters(parseAbiParameters('uint256, uint256'), [shares, assets]);
  return mockLog({address: HUB, topics, data});
}

const handle = createTargetHandler(NETWORK, TARGET);

describe('fee-shares-minter workflow', () => {
  test('returns evaluated=0 when assetCount is 0', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({getAssetCount: () => 0n});

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 0 assets, minted 0, skipped 0');
  });

  test('skips every asset when checkUpkeep is false for all', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({
      getAssetCount: () => 3n,
      checkUpkeep: (_, checkData) => ({upkeepNeeded: false, performData: checkData}),
    });

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 3 assets, minted 0, skipped 3');
  });

  test('counts submission-skipped when estimateGas reverts', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({
      getAssetCount: () => 1n,
      checkUpkeep: (_, checkData) => ({upkeepNeeded: true, performData: checkData}),
    });
    evmMock.estimateGas = () => {
      throw new Error('reverted');
    };

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 1 assets, minted 0, skipped 1');
  });

  test('submits and parses MintFeeShares on happy path across all assets', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({
      getAssetCount: () => 2n,
      checkUpkeep: (_, checkData) => ({upkeepNeeded: true, performData: checkData}),
    });
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});

    let receiptCallNum = 0n;
    evmMock.getTransactionReceipt = () => {
      const assetId = receiptCallNum++;
      return {
        receipt: mockReceipt({
          txHash: TX_HASH,
          logs: [mintFeeSharesLog(assetId, 100n + assetId, 200n + assetId)],
        }),
      };
    };

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 2 assets, minted 2, skipped 0');

    const logs = runtime.getLogs();
    expect(logs.find((l) => l.includes('asset=0') && l.includes('shares=100'))).toBeDefined();
    expect(logs.find((l) => l.includes('asset=1') && l.includes('shares=101'))).toBeDefined();
  });

  test('mixes mintable and skipped assets in a single tick', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({
      getAssetCount: () => 3n,
      checkUpkeep: (assetId, checkData) => ({
        upkeepNeeded: assetId !== 1n,
        performData: checkData,
      }),
    });
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});

    let mintAssetId = 0n;
    evmMock.getTransactionReceipt = () => {
      const id = mintAssetId === 0n ? 0n : 2n;
      mintAssetId = 2n;
      return {
        receipt: mockReceipt({
          txHash: TX_HASH,
          logs: [mintFeeSharesLog(id, 1n, 1n)],
        }),
      };
    };

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 3 assets, minted 2, skipped 1');
  });

  test('logs "no MintFeeShares" when receipt has no matching event', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = dispatchCallContract({
      getAssetCount: () => 1n,
      checkUpkeep: (_, checkData) => ({upkeepNeeded: true, performData: checkData}),
    });
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});
    evmMock.getTransactionReceipt = () => ({receipt: mockReceipt({txHash: TX_HASH})});

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('evaluated 1 assets, minted 1, skipped 0');
    expect(runtime.getLogs().find((l) => l.includes('no MintFeeShares event found'))).toBeDefined();
  });
});
