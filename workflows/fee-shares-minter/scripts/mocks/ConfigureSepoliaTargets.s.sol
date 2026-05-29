// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {IFeeSharesMinter} from '../../src/IFeeSharesMinter.sol';
import {MockHub} from '../../tests/mocks/MockHub.sol';

// forge script workflows/fee-shares-minter/scripts/mocks/ConfigureSepoliaTargets.s.sol:ConfigureSepoliaTargets \
//   --rpc-url sepolia --account $ACCOUNT_NAME --slow -vvvv [--broadcast]
contract ConfigureSepoliaTargets is Script {
  address internal constant MINTER = 0x4Be1891E0a1e01270E594059FEE4E258C31eCE45;
  uint16 internal constant THRESHOLD_BPS = 1;

  function run() external {
    address[3] memory hubs = [
      0x537419DB0a931AEC35cD9C01a5EE370D16F931CD,
      0x1a80F05d34E9fC2e89ae70D35DF1Da259E2bfB01,
      0x9Ce749C045b7d0d3aC1313C04f995FC697a31Aa8
    ];

    vm.startBroadcast();
    for (uint256 i = 0; i < hubs.length; i++) {
      uint256 assetCount = MockHub(hubs[i]).getAssetCount();
      for (uint256 assetId = 0; assetId < assetCount; assetId++) {
        IFeeSharesMinter(MINTER).setConfig(hubs[i], assetId, THRESHOLD_BPS);
        console.log('setConfig hub=%s assetId=%s', hubs[i], assetId);
      }
    }
    vm.stopBroadcast();
  }
}
