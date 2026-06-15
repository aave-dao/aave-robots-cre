// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';

import {AaveCREOperator} from 'aave-cre/AaveCREOperator.sol';
import {IAaveCREOperator} from 'aave-cre/IAaveCREOperator.sol';
import {IWorkflowRegistry} from 'aave-cre/IWorkflowRegistry.sol';

import {MockWorkflowRegistry} from './helpers/MockWorkflowRegistry.sol';

abstract contract AaveCREOperatorTestBase is Test {
  AaveCREOperator internal operator;
  MockWorkflowRegistry internal registry;

  address internal owner;
  address internal guardian;
  address internal anyone;

  string internal constant DON_FAMILY = 'aave-don';
  string internal constant OTHER_DON_FAMILY = 'aave-don-2';
  string internal constant WORKFLOW_NAME = 'aave-fee-shares-minter';
  string internal constant TAG = 'v1';
  bytes32 internal constant WORKFLOW_ID = bytes32(uint256(0xA11CE));
  bytes32 internal constant NEW_WORKFLOW_ID = bytes32(uint256(0xB0B));
  string internal constant BINARY_URL = 'https://example.com/binary.wasm';
  string internal constant CONFIG_URL = 'https://example.com/config.json';

  function setUp() public virtual {
    _setUpEnvironment();
    anyone = makeAddr('anyone');

    registry = new MockWorkflowRegistry();
    operator = new AaveCREOperator(owner, guardian, address(registry));

    registry.setDONLimit(DON_FAMILY, 10);
    registry.setDONLimit(OTHER_DON_FAMILY, 10);

    vm.prank(owner);
    operator.linkOwner(0, bytes32(0), '');
  }

  function _setUpEnvironment() internal virtual {
    owner = makeAddr('owner');
    guardian = makeAddr('guardian');
  }

  function test_constructor_setsOwnerGuardianAndRegistry() public view {
    assertEq(operator.owner(), owner);
    assertEq(operator.guardian(), guardian);
    assertEq(operator.getRegistry(), address(registry));
  }

  function test_constructor_revertsWith_InvalidZeroAddress() public {
    vm.expectRevert(IAaveCREOperator.InvalidZeroAddress.selector);
    new AaveCREOperator(owner, guardian, address(0));
  }

  function test_linkOwner_byOwner() public view {
    assertTrue(registry.isLinked(address(operator)));
  }

  function test_linkOwner_revertsWhenCalledByGuardian() public {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    operator.linkOwner(0, bytes32(0), '');
  }

  function test_upsertWorkflow_byOwner_creates() public {
    _upsertActive();

    MockWorkflowRegistry.Workflow memory wf = registry.getWorkflow(WORKFLOW_ID);
    assertTrue(wf.exists);
    assertEq(wf.owner, address(operator));
    assertEq(wf.workflowId, WORKFLOW_ID);
    assertEq(uint8(wf.status), uint8(IWorkflowRegistry.WorkflowStatus.ACTIVE));
  }

  function test_upsertWorkflow_byOwner_updatesWorkflowId() public {
    _upsertActive();

    vm.prank(owner);
    _upsertCall(NEW_WORKFLOW_ID, IWorkflowRegistry.WorkflowStatus.ACTIVE, DON_FAMILY);

    assertEq(registry.getWorkflow(NEW_WORKFLOW_ID).workflowId, NEW_WORKFLOW_ID);
  }

  function test_upsertWorkflow_revertsWhenCalledByGuardian() public {
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    _upsertActiveCall();
  }

  function test_upsertWorkflow_revertsWhenCalledByAnyone() public {
    vm.prank(anyone);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
    _upsertActiveCall();
  }

  function test_upsertWorkflow_propagatesRegistryRevert_whenDonLimitNotSet() public {
    vm.prank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(MockWorkflowRegistry.DonLimitNotSet.selector, 'unconfigured-don')
    );
    _upsertCall(WORKFLOW_ID, IWorkflowRegistry.WorkflowStatus.ACTIVE, 'unconfigured-don');
  }

  function test_upsertWorkflow_propagatesRegistryRevert_whenZeroWorkflowId() public {
    vm.prank(owner);
    vm.expectRevert(MockWorkflowRegistry.ZeroWorkflowIDNotAllowed.selector);
    _upsertCall(bytes32(0), IWorkflowRegistry.WorkflowStatus.ACTIVE, DON_FAMILY);
  }

  function test_pauseWorkflow_byOwner() public {
    _upsertActive();

    vm.expectEmit(address(operator));
    emit IAaveCREOperator.WorkflowPaused(WORKFLOW_ID, owner);

    vm.prank(owner);
    operator.pauseWorkflow(WORKFLOW_ID);

    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.PAUSED)
    );
  }

  function test_pauseWorkflow_byGuardian() public {
    _upsertActive();

    vm.expectEmit(address(operator));
    emit IAaveCREOperator.WorkflowPaused(WORKFLOW_ID, guardian);

    vm.prank(guardian);
    operator.pauseWorkflow(WORKFLOW_ID);

    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.PAUSED)
    );
  }

  function test_pauseWorkflow_revertsWhenCalledByAnyone() public {
    _upsertActive();
    vm.prank(anyone);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, anyone)
    );
    operator.pauseWorkflow(WORKFLOW_ID);
  }

  function test_pauseWorkflow_propagatesRegistryRevert_whenWorkflowMissing() public {
    vm.prank(guardian);
    vm.expectRevert(MockWorkflowRegistry.WorkflowDoesNotExist.selector);
    operator.pauseWorkflow(NEW_WORKFLOW_ID);
  }

  function test_batchPauseWorkflows_byGuardian() public {
    _upsertActive();
    bytes32[] memory ids = new bytes32[](1);
    ids[0] = WORKFLOW_ID;

    vm.expectEmit(address(operator));
    emit IAaveCREOperator.WorkflowPaused(WORKFLOW_ID, guardian);

    vm.prank(guardian);
    operator.batchPauseWorkflows(ids);

    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.PAUSED)
    );
  }

  function test_batchPauseWorkflows_revertsWhenCalledByAnyone() public {
    bytes32[] memory ids = new bytes32[](1);
    ids[0] = WORKFLOW_ID;
    vm.prank(anyone);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, anyone)
    );
    operator.batchPauseWorkflows(ids);
  }

  function test_activateWorkflow_byOwner() public {
    _upsertActive();
    vm.prank(guardian);
    operator.pauseWorkflow(WORKFLOW_ID);

    vm.prank(owner);
    operator.activateWorkflow(WORKFLOW_ID, DON_FAMILY);

    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.ACTIVE)
    );
  }

  function test_activateWorkflow_revertsWhenCalledByGuardian() public {
    _upsertActive();
    vm.prank(guardian);
    operator.pauseWorkflow(WORKFLOW_ID);

    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    operator.activateWorkflow(WORKFLOW_ID, DON_FAMILY);
  }

  function test_batchActivateWorkflows_byOwner() public {
    _upsertActive();
    vm.prank(guardian);
    operator.pauseWorkflow(WORKFLOW_ID);

    bytes32[] memory ids = new bytes32[](1);
    ids[0] = WORKFLOW_ID;
    vm.prank(owner);
    operator.batchActivateWorkflows(ids, DON_FAMILY);

    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.ACTIVE)
    );
  }

  function test_batchActivateWorkflows_revertsWhenCalledByGuardian() public {
    bytes32[] memory ids = new bytes32[](1);
    ids[0] = WORKFLOW_ID;
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    operator.batchActivateWorkflows(ids, DON_FAMILY);
  }

  function test_pauseThenActivate_roundTrip() public {
    _upsertActive();

    vm.prank(guardian);
    operator.pauseWorkflow(WORKFLOW_ID);
    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.PAUSED)
    );

    vm.prank(owner);
    operator.activateWorkflow(WORKFLOW_ID, DON_FAMILY);
    assertEq(
      uint8(registry.getWorkflow(WORKFLOW_ID).status),
      uint8(IWorkflowRegistry.WorkflowStatus.ACTIVE)
    );
  }

  function test_deleteWorkflow_byOwner() public {
    _upsertActive();

    vm.prank(owner);
    operator.deleteWorkflow(WORKFLOW_ID);

    assertFalse(registry.getWorkflow(WORKFLOW_ID).exists);
  }

  function test_deleteWorkflow_revertsWhenCalledByGuardian() public {
    _upsertActive();
    vm.prank(guardian);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
    operator.deleteWorkflow(WORKFLOW_ID);
  }

  function test_updateWorkflowDONFamily_byOwner() public {
    _upsertActive();

    vm.prank(owner);
    operator.updateWorkflowDONFamily(WORKFLOW_ID, OTHER_DON_FAMILY);

    assertEq(registry.getWorkflow(WORKFLOW_ID).donHash, keccak256(bytes(OTHER_DON_FAMILY)));
  }

  function test_updateWorkflowDONFamily_revertsWhenCalledByAnyone() public {
    _upsertActive();
    vm.prank(anyone);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
    operator.updateWorkflowDONFamily(WORKFLOW_ID, OTHER_DON_FAMILY);
  }

  function test_allowlistRequest_byOwner() public {
    bytes32 digest = keccak256('request');
    uint32 expiry = uint32(block.timestamp + 1 days);

    vm.prank(owner);
    operator.allowlistRequest(digest, expiry);

    assertEq(
      registry.allowlistedRequests(keccak256(abi.encode(address(operator), digest))),
      expiry
    );
  }

  function test_allowlistRequest_revertsWhenCalledByAnyone() public {
    vm.prank(anyone);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
    operator.allowlistRequest(keccak256('request'), uint32(block.timestamp + 1 days));
  }

  function test_setRegistry_byOwner() public {
    address newRegistry = address(new MockWorkflowRegistry());

    vm.expectEmit(address(operator));
    emit IAaveCREOperator.WorkflowRegistrySet(newRegistry);

    vm.prank(owner);
    operator.setRegistry(newRegistry);

    assertEq(operator.getRegistry(), newRegistry);
  }

  function test_setRegistry_revertsWhenCalledByAnyone() public {
    vm.prank(anyone);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
    operator.setRegistry(makeAddr('newRegistry'));
  }

  function test_setRegistry_revertsWith_InvalidZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IAaveCREOperator.InvalidZeroAddress.selector);
    operator.setRegistry(address(0));
  }

  function test_transferOwnership_isTwoStep() public {
    address newOwner = makeAddr('newOwner');

    vm.prank(owner);
    operator.transferOwnership(newOwner);
    assertEq(operator.owner(), owner);
    assertEq(operator.pendingOwner(), newOwner);

    vm.prank(newOwner);
    operator.acceptOwnership();
    assertEq(operator.owner(), newOwner);
  }

  function test_transferOwnership_revertsWhenCalledByAnyone() public {
    vm.prank(anyone);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
    operator.transferOwnership(anyone);
  }

  function test_updateGuardian_byOwner() public {
    address newGuardian = makeAddr('newGuardian');

    vm.expectEmit(address(operator));
    emit IWithGuardian.GuardianUpdated(guardian, newGuardian);

    vm.prank(owner);
    operator.updateGuardian(newGuardian);
    assertEq(operator.guardian(), newGuardian);
  }

  function test_updateGuardian_byGuardian() public {
    address newGuardian = makeAddr('newGuardian');
    vm.prank(guardian);
    operator.updateGuardian(newGuardian);
    assertEq(operator.guardian(), newGuardian);
  }

  function test_updateGuardian_revertsWhenCalledByAnyone() public {
    vm.prank(anyone);
    vm.expectRevert(
      abi.encodeWithSelector(IWithGuardian.OnlyGuardianOrOwnerInvalidCaller.selector, anyone)
    );
    operator.updateGuardian(anyone);
  }

  function _upsertActive() internal {
    vm.prank(owner);
    _upsertActiveCall();
  }

  function _upsertActiveCall() internal {
    _upsertCall(WORKFLOW_ID, IWorkflowRegistry.WorkflowStatus.ACTIVE, DON_FAMILY);
  }

  function _upsertCall(
    bytes32 workflowId,
    IWorkflowRegistry.WorkflowStatus status,
    string memory donFamily
  ) internal {
    operator.upsertWorkflow(
      WORKFLOW_NAME,
      TAG,
      workflowId,
      status,
      donFamily,
      BINARY_URL,
      CONFIG_URL,
      '',
      true
    );
  }
}
