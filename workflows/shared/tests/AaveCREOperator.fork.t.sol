// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

import {AaveCREOperatorTestBase} from './AaveCREOperatorTestBase.sol';

contract AaveCREOperatorForkTest is AaveCREOperatorTestBase {
  function _setUpEnvironment() internal override {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
    }
    vm.createSelectFork(rpc);

    owner = GovernanceV3Ethereum.EXECUTOR_LVL_1;
    guardian = GovernanceV3Ethereum.GOVERNANCE_GUARDIAN;
  }
}
