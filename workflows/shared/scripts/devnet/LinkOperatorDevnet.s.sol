// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from 'forge-std/Script.sol';

import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';

// Links the deployed AaveCREOperator as a workflow owner on the registry.
//
// 1. Set the operator as `devnet-settings.account.workflow-owner-address` in project.yaml.
// 2. Generate the ownership proof:
//      npm --prefix workflows/shared/offchain run link-operator:devnet:unsigned
// 3. Paste the deployed operator address into OPERATOR and the `data` field of that
//    unsigned transaction into LINK_CALLDATA below (it is identical to the operator's
//    own linkOwner calldata — same selector).
// 4. Run, impersonating the operator's owner on the tenderly devnet (mainnet fork):
//      forge script workflows/shared/scripts/devnet/LinkOperatorDevnet.s.sol:LinkOperatorDevnet \
//        --rpc-url tenderly_devnet --unlocked --broadcast -vvvv
contract LinkOperatorDevnet is Script {
  address internal constant OPERATOR = 0x0000000000000000000000000000000000000000; // TODO: deployed operator address
  bytes internal constant LINK_CALLDATA = hex''; // TODO: `data` from link-operator:devnet:unsigned

  function run() external {
    vm.startBroadcast(GovernanceV3Ethereum.EXECUTOR_LVL_1);
    (bool ok, bytes memory ret) = OPERATOR.call(LINK_CALLDATA);
    require(ok, string(ret));
    vm.stopBroadcast();

    console.log('Linked operator as workflow owner:', OPERATOR);
  }
}
