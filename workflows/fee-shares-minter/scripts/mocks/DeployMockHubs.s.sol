// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {MockHub} from '../../tests/mocks/MockHub.sol';

// MOCK_HUB_COUNT=3 forge script workflows/fee-shares-minter/scripts/mocks/DeployMockHubs.s.sol:DeployMockHubs \
//   --rpc-url sepolia --account $ACCOUNT_NAME --slow -vvvv [--broadcast --verify]
contract DeployMockHubs is Script {
  uint256 internal constant DEFAULT_ASSET_COUNT = 3;

  function run() external {
    uint256 hubCount = vm.envOr('MOCK_HUB_COUNT', uint256(3));

    vm.startBroadcast();
    for (uint256 i = 0; i < hubCount; i++) {
      MockHub hub = new MockHub();
      hub.setAssetCount(DEFAULT_ASSET_COUNT);
      for (uint256 assetId = 0; assetId < DEFAULT_ASSET_COUNT; assetId++) {
        hub.setCanMint(assetId, true);
      }
      console.log('MockHub %s: %s', i, address(hub));
    }
    vm.stopBroadcast();
  }
}
