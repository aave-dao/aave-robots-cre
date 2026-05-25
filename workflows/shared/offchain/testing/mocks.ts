import {encodeAbiParameters, hexToBytes, parseAbiParameters, type Hex} from 'viem';

const EMPTY_HASH = new Uint8Array(32);
const EMPTY_ADDR = new Uint8Array(20);

export function encodeCheckUpkeepResult(needed: boolean, performData: Hex): Uint8Array {
  return hexToBytes(encodeAbiParameters(parseAbiParameters('bool, bytes'), [needed, performData]));
}

export type MockLog = ReturnType<typeof mockLog>;

export function mockLog(params: {address: Hex; topics: readonly Hex[]; data: Hex}) {
  return {
    address: hexToBytes(params.address),
    topics: params.topics.map((t) => hexToBytes(t)),
    txHash: EMPTY_HASH,
    blockHash: EMPTY_HASH,
    data: hexToBytes(params.data),
    eventSig: params.topics.length > 0 ? hexToBytes(params.topics[0]) : EMPTY_HASH,
    txIndex: 0,
    index: 0,
    removed: false,
  };
}

export function mockReceipt(params: {txHash: Hex; logs?: MockLog[]; status?: bigint}) {
  return {
    status: params.status ?? 1n,
    gasUsed: 100_000n,
    txIndex: 0n,
    blockHash: EMPTY_HASH,
    logs: params.logs ?? [],
    txHash: hexToBytes(params.txHash),
    contractAddress: EMPTY_ADDR,
  };
}
