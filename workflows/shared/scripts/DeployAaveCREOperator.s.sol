// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

import {AaveCREOperator} from 'aave-cre/AaveCREOperator.sol';

// make deploy-cre-operator env=Mainnet [dry=1]
// make deploy-cre-operator env=Devnet  [dry=1]
contract DeployAaveCREOperator is Script {
  // Chainlink CRE WorkflowRegistry v2.0.0 on Ethereum mainnet. The tenderly devnet
  // is a mainnet fork, so the same address applies there.
  address internal constant DEFAULT_WORKFLOW_REGISTRY = 0x4Ac54353FA4Fa961AfcC5ec4B118596d3305E7e5;

  function run() external returns (address) {
    address owner = GovernanceV3Ethereum.EXECUTOR_LVL_1;
    address guardian = GovernanceV3Ethereum.GOVERNANCE_GUARDIAN;
    address registry = vm.envOr('WORKFLOW_REGISTRY', DEFAULT_WORKFLOW_REGISTRY);

    require(owner != address(0), 'invalid owner');
    require(guardian != address(0), 'invalid guardian');
    require(registry != address(0), 'invalid registry');

    vm.startBroadcast();
    AaveCREOperator operator = new AaveCREOperator(owner, guardian, registry);
    vm.stopBroadcast();

    console.log('AaveCREOperator deployed at:', address(operator));
    console.log('Owner:', owner);
    console.log('Guardian:', guardian);
    console.log('WorkflowRegistry:', registry);

    return address(operator);
  }
}
