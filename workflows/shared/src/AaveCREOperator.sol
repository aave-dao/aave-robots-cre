// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2StepWithGuardian} from 'solidity-utils/contracts/access-control/Ownable2StepWithGuardian.sol';

import {IWorkflowRegistry} from './IWorkflowRegistry.sol';
import {IAaveCREOperator} from './IAaveCREOperator.sol';

/// @title AaveCREOperator
/// @author Aave Labs
/// @notice Lightweight operator that owns Aave's Chainlink CRE workflows on the
/// `WorkflowRegistry` (v2), shared by every robot in this repo. The operator links
/// itself as a workflow owner and all workflow admin actions flow through it. The
/// owner has full control; the guardian may only pause in case of emergency.
contract AaveCREOperator is Ownable2StepWithGuardian, IAaveCREOperator {
  IWorkflowRegistry internal _registry;

  constructor(
    address initialOwner,
    address initialGuardian,
    address workflowRegistry
  ) Ownable2StepWithGuardian(initialOwner, initialGuardian) {
    _setRegistry(workflowRegistry);
  }

  /// @inheritdoc IAaveCREOperator
  function linkOwner(
    uint256 validityTimestamp,
    bytes32 proof,
    bytes calldata signature
  ) external onlyOwner {
    _registry.linkOwner(validityTimestamp, proof, signature);
  }

  /// @inheritdoc IAaveCREOperator
  function upsertWorkflow(
    string calldata workflowName,
    string calldata tag,
    bytes32 workflowId,
    IWorkflowRegistry.WorkflowStatus status,
    string calldata donFamily,
    string calldata binaryUrl,
    string calldata configUrl,
    bytes calldata attributes,
    bool keepAlive
  ) external onlyOwner {
    _registry.upsertWorkflow(
      workflowName,
      tag,
      workflowId,
      status,
      donFamily,
      binaryUrl,
      configUrl,
      attributes,
      keepAlive
    );
  }

  /// @inheritdoc IAaveCREOperator
  function pauseWorkflow(bytes32 workflowId) external onlyOwnerOrGuardian {
    _registry.pauseWorkflow(workflowId);
    emit WorkflowPaused(workflowId, _msgSender());
  }

  /// @inheritdoc IAaveCREOperator
  function batchPauseWorkflows(bytes32[] calldata workflowIds) external onlyOwnerOrGuardian {
    _registry.batchPauseWorkflows(workflowIds);
    for (uint256 i = 0; i < workflowIds.length; i++) {
      emit WorkflowPaused(workflowIds[i], _msgSender());
    }
  }

  /// @inheritdoc IAaveCREOperator
  function activateWorkflow(bytes32 workflowId, string calldata donFamily) external onlyOwner {
    _registry.activateWorkflow(workflowId, donFamily);
  }

  /// @inheritdoc IAaveCREOperator
  function batchActivateWorkflows(
    bytes32[] calldata workflowIds,
    string calldata donFamily
  ) external onlyOwner {
    _registry.batchActivateWorkflows(workflowIds, donFamily);
  }

  /// @inheritdoc IAaveCREOperator
  function deleteWorkflow(bytes32 workflowId) external onlyOwner {
    _registry.deleteWorkflow(workflowId);
  }

  /// @inheritdoc IAaveCREOperator
  function updateWorkflowDONFamily(
    bytes32 workflowId,
    string calldata newDonFamily
  ) external onlyOwner {
    _registry.updateWorkflowDONFamily(workflowId, newDonFamily);
  }

  /// @inheritdoc IAaveCREOperator
  function allowlistRequest(bytes32 requestDigest, uint32 expiryTimestamp) external onlyOwner {
    _registry.allowlistRequest(requestDigest, expiryTimestamp);
  }

  /// @inheritdoc IAaveCREOperator
  function setRegistry(address workflowRegistry) external onlyOwner {
    _setRegistry(workflowRegistry);
  }

  /// @inheritdoc IAaveCREOperator
  function getRegistry() external view returns (address) {
    return address(_registry);
  }

  function _setRegistry(address workflowRegistry) internal {
    require(workflowRegistry != address(0), InvalidZeroAddress());
    _registry = IWorkflowRegistry(workflowRegistry);
    emit WorkflowRegistrySet(workflowRegistry);
  }
}
