// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

import {FeeSharesMinter} from '../src/FeeSharesMinter.sol';

abstract contract BaseDeploy is Script {
  function _run(address owner) internal returns (address) {
    require(owner != address(0), 'invalid owner');
    vm.startBroadcast();
    FeeSharesMinter minter = new FeeSharesMinter(owner);
    vm.stopBroadcast();
    console.log('FeeSharesMinter deployed at:', address(minter));
    console.log('Owner:', owner);
    return address(minter);
  }
}

contract DeployMainnet is BaseDeploy {
  function run() external returns (address) {
    return _run(GovernanceV3Ethereum.EXECUTOR_LVL_1);
  }
}
