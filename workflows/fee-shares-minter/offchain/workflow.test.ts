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
import {encodeCheckUpkeepResult, mockLog, mockReceipt} from '../../shared/offchain/testing/mocks';
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
const ASSET_ID = 5;
const TX_HASH = ('0xab' + 'cd'.repeat(31)) as Hex;

const TARGET = {minter: MINTER, hub: HUB, assetId: ASSET_ID};
const CONFIG = {schedule: '* * * * *', evms: [{chainName: CHAIN_NAME, targets: [TARGET]}]};

const PERFORM_DATA = encodeAbiParameters(parseAbiParameters('address, uint256'), [
  HUB,
  BigInt(ASSET_ID),
]) as Hex;

function makeRuntime() {
  const runtime = newTestRuntime();
  (runtime as unknown as {config: typeof CONFIG}).config = CONFIG;
  return runtime;
}

function mintFeeSharesLog(shares: bigint, assets: bigint) {
  const topics = encodeEventTopics({
    abi: IHubABI,
    eventName: 'MintFeeShares',
    args: {assetId: BigInt(ASSET_ID), feeReceiver: FEE_RECEIVER},
  }) as readonly Hex[];
  const data = encodeAbiParameters(parseAbiParameters('uint256, uint256'), [shares, assets]);
  return mockLog({address: HUB, topics, data});
}

const handle = createTargetHandler(CHAIN_NAME, TARGET);

describe('fee-shares-minter workflow', () => {
  test('returns "No upkeep needed" when checkUpkeep is false', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = () => ({data: encodeCheckUpkeepResult(false, PERFORM_DATA)});

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('No upkeep needed');
  });

  test('returns "Submission skipped" when estimateGas reverts', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = () => ({data: encodeCheckUpkeepResult(true, PERFORM_DATA)});
    evmMock.estimateGas = () => {
      throw new Error('reverted');
    };

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe('Submission skipped');
  });

  test('submits and parses MintFeeShares event on happy path', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = () => ({data: encodeCheckUpkeepResult(true, PERFORM_DATA)});
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});
    evmMock.getTransactionReceipt = () => ({
      receipt: mockReceipt({txHash: TX_HASH, logs: [mintFeeSharesLog(123n, 456n)]}),
    });

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe(TX_HASH);

    const minted = runtime.getLogs().find((l) => l.includes('MintFeeShares'));
    expect(minted).toBeDefined();
    expect(minted).toContain('shares=123');
    expect(minted).toContain('assets=456');
    expect(minted).toContain(`assetId=${ASSET_ID}`);
    expect(minted!.toLowerCase()).toContain(FEE_RECEIVER.toLowerCase());
    expect(minted!.toLowerCase()).toContain(HUB.toLowerCase());
  });

  test('logs "no MintFeeShares" when receipt has no matching log', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = () => ({data: encodeCheckUpkeepResult(true, PERFORM_DATA)});
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});
    evmMock.getTransactionReceipt = () => ({receipt: mockReceipt({txHash: TX_HASH})});

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe(TX_HASH);
    expect(runtime.getLogs().find((l) => l.includes('no MintFeeShares event found'))).toBeDefined();
  });

  test('ignores logs from non-hub addresses', () => {
    const evmMock = EvmMock.testInstance(CHAIN_SELECTOR);
    evmMock.callContract = () => ({data: encodeCheckUpkeepResult(true, PERFORM_DATA)});
    evmMock.estimateGas = () => ({gas: 100_000n});
    evmMock.writeReport = () => ({txStatus: TxStatus.SUCCESS, txHash: hexToBytes(TX_HASH)});

    const wrongAddrLog = {
      ...mintFeeSharesLog(999n, 999n),
      address: hexToBytes('0x4444444444444444444444444444444444444444' as Hex),
    };
    evmMock.getTransactionReceipt = () => ({
      receipt: mockReceipt({txHash: TX_HASH, logs: [wrongAddrLog]}),
    });

    const runtime = makeRuntime();
    expect(handle(runtime as never)).toBe(TX_HASH);
    expect(runtime.getLogs().find((l) => l.includes('no MintFeeShares event found'))).toBeDefined();
  });
});
