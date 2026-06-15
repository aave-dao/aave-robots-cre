// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWorkflowRegistry} from './IWorkflowRegistry.sol';

/// @title IAaveCREOperator
/// @author Aave Labs
/// @notice Owner/guardian-controlled operator that owns Aave's CRE workflows on
/// the Chainlink `WorkflowRegistry` (v2). The operator is the registry-level
/// workflow owner: it links itself, upserts, activates, deletes and reassigns
/// workflows (owner-only), while the guardian can additionally pause them as an
/// emergency brake.
interface IAaveCREOperator {
  /// @notice Emitted when a workflow is paused through the operator.
  /// @param workflowId The workflow identifier.
  /// @param pausedBy The caller that paused the workflow (owner or guardian).
  event WorkflowPaused(bytes32 indexed workflowId, address indexed pausedBy);

  /// @notice Emitted when the workflow registry address is set.
  /// @param workflowRegistry The new workflow registry.
  event WorkflowRegistrySet(address indexed workflowRegistry);

  /// @notice Thrown when a zero address is supplied where it is not allowed.
  error InvalidZeroAddress();

  /// @notice Links the operator as a workflow owner on the registry. Owner only.
  /// @param validityTimestamp The timestamp until which the proof is valid.
  /// @param proof The ownership proof to submit.
  /// @param signature The signature of the ownership proof metadata, signed by an allowed signer.
  function linkOwner(uint256 validityTimestamp, bytes32 proof, bytes calldata signature) external;

  /// @notice Creates or updates a workflow owned by this operator. Owner only.
  /// @param workflowName Human-readable name.
  /// @param tag Unique tag per `(operator, workflowName)`.
  /// @param workflowId Deterministic, globally-unique identifier computed off-chain.
  /// @param status Initial status (ACTIVE or PAUSED).
  /// @param donFamily Human-readable DON family label.
  /// @param binaryUrl URL of the WASM binary (required).
  /// @param configUrl URL of the config (optional).
  /// @param attributes Arbitrary bytes for additional workflow details (optional).
  /// @param keepAlive Whether existing workflows sharing the name should be kept active.
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
  ) external;

  /// @notice Pauses a workflow owned by this operator. Owner or guardian.
  /// @param workflowId The workflow identifier.
  function pauseWorkflow(bytes32 workflowId) external;

  /// @notice Pauses multiple workflows owned by this operator. Owner or guardian.
  /// @param workflowIds The workflow identifiers; must not be empty.
  function batchPauseWorkflows(bytes32[] calldata workflowIds) external;

  /// @notice Activates a paused workflow owned by this operator. Owner only.
  /// @param workflowId The workflow identifier.
  /// @param donFamily The target DON family.
  function activateWorkflow(bytes32 workflowId, string calldata donFamily) external;

  /// @notice Activates multiple paused workflows owned by this operator. Owner only.
  /// @param workflowIds The workflow identifiers; must not be empty.
  /// @param donFamily The target DON family.
  function batchActivateWorkflows(
    bytes32[] calldata workflowIds,
    string calldata donFamily
  ) external;

  /// @notice Deletes a workflow owned by this operator. Owner only.
  /// @param workflowId The workflow identifier.
  function deleteWorkflow(bytes32 workflowId) external;

  /// @notice Reassigns the DON family of an active workflow owned by this operator. Owner only.
  /// @param workflowId The workflow identifier.
  /// @param newDonFamily The new DON family.
  function updateWorkflowDONFamily(bytes32 workflowId, string calldata newDonFamily) external;

  /// @notice Allowlists an off-chain request digest on behalf of this operator. Owner only.
  /// @param requestDigest The hash of the request payload.
  /// @param expiryTimestamp The timestamp until which the request is valid.
  function allowlistRequest(bytes32 requestDigest, uint32 expiryTimestamp) external;

  /// @notice Updates the workflow registry the operator drives. Owner only.
  /// @param workflowRegistry The new workflow registry address.
  function setRegistry(address workflowRegistry) external;

  /// @notice Returns the workflow registry the operator currently drives.
  function getRegistry() external view returns (address);
}
