// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

import {FeeSharesMinter} from '../src/FeeSharesMinter.sol';

abstract contract BaseDeploy is Script {
  function _run(address owner, address guardian) internal returns (address) {
    require(owner != address(0), 'invalid owner');
    require(guardian != address(0), 'invalid guardian');
    vm.startBroadcast();
    FeeSharesMinter minter = new FeeSharesMinter(owner, guardian);
    vm.stopBroadcast();
    console.log('FeeSharesMinter deployed at:', address(minter));
    console.log('Owner:', owner);
    console.log('Guardian:', guardian);
    return address(minter);
  }
}

// make deploy-mainnet-fee-shares-minter-dry  # simulate
// make deploy-mainnet-fee-shares-minter      # broadcast
contract DeployMainnet is BaseDeploy {
  function run() external returns (address) {
    return _run(GovernanceV3Ethereum.EXECUTOR_LVL_1, GovernanceV3Ethereum.GOVERNANCE_GUARDIAN);
  }
}

// make deploy-sepolia-fee-shares-minter-dry  # simulate (requires SEPOLIA_OWNER in .env)
// make deploy-sepolia-fee-shares-minter      # broadcast
contract DeploySepolia is BaseDeploy {
  function run() external returns (address) {
    address owner = vm.envAddress('SEPOLIA_OWNER');
    address guardian = vm.envOr('SEPOLIA_GUARDIAN', owner);
    return _run(owner, guardian);
  }
}
