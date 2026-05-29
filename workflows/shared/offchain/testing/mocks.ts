import {
  decodeAbiParameters,
  decodeFunctionData,
  encodeAbiParameters,
  hexToBytes,
  parseAbiParameters,
  toFunctionSelector,
  type Hex,
} from 'viem';
import {IAaveCREReceiverABI} from '../abi/IAaveCREReceiver';

const EMPTY_HASH = new Uint8Array(32);
const EMPTY_ADDR = new Uint8Array(20);

export function encodeCheckUpkeepResult(needed: boolean, performData: Hex): Uint8Array {
  return hexToBytes(encodeAbiParameters(parseAbiParameters('bool, bytes'), [needed, performData]));
}

export function encodeUint256Result(value: bigint): Uint8Array {
  return hexToBytes(encodeAbiParameters(parseAbiParameters('uint256'), [value]));
}

export const GET_ASSET_COUNT_SELECTOR = toFunctionSelector(
  'function getAssetCount() view returns (uint256)',
);
export const CHECK_UPKEEP_SELECTOR = toFunctionSelector(
  'function checkUpkeep(bytes) view returns (bool, bytes)',
);

export type CallContractInput = {call: {data: Uint8Array; to: Uint8Array}};

export function dispatchCallContract(handlers: {
  getAssetCount?: () => bigint;
  checkUpkeep?: (assetId: bigint, checkData: Hex) => {upkeepNeeded: boolean; performData: Hex};
}) {
  return (req: CallContractInput): {data: Uint8Array} => {
    const data = ('0x' +
      Array.from(req.call.data)
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')) as Hex;
    const selector = data.slice(0, 10).toLowerCase();

    if (selector === GET_ASSET_COUNT_SELECTOR && handlers.getAssetCount) {
      return {data: encodeUint256Result(handlers.getAssetCount())};
    }
    if (selector === CHECK_UPKEEP_SELECTOR && handlers.checkUpkeep) {
      const [checkData] = decodeFunctionData({abi: IAaveCREReceiverABI, data}).args as [Hex];
      const [, assetId] = decodeAbiParameters(parseAbiParameters('address, uint256'), checkData);
      const {upkeepNeeded, performData} = handlers.checkUpkeep(assetId, checkData);
      return {data: encodeCheckUpkeepResult(upkeepNeeded, performData)};
    }
    throw new Error(`dispatchCallContract: unmocked selector ${selector}`);
  };
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
