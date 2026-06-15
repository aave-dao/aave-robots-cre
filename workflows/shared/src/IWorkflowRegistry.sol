// SPDX-License-Identifier: MIT
// Minimal interface for the Chainlink CRE WorkflowRegistry v2.0.0.
// Mirrors the subset of
// https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/cre/src/v2/WorkflowRegistry.sol
// that AaveCREOperator drives.
pragma solidity ^0.8.0;

/// @title IWorkflowRegistry
/// @author Aave Labs
/// @notice The Chainlink CRE registry (v2) that holds workflow metadata and status.
/// Workflows are owned by the `msg.sender` that calls `upsertWorkflow`; the owner
/// (here, the AaveCREOperator) must first be linked through `linkOwner`. Workflow
/// lifecycle actions are keyed by the off-chain computed `workflowId`.
interface IWorkflowRegistry {
  enum WorkflowStatus {
    ACTIVE,
    PAUSED
  }

  /// @notice Links the caller as a workflow owner using a signed ownership proof.
  /// @param validityTimestamp The timestamp until which the proof is valid.
  /// @param proof The ownership proof to submit.
  /// @param signature The signature of the ownership proof metadata, signed by an allowed signer.
  function linkOwner(uint256 validityTimestamp, bytes32 proof, bytes calldata signature) external;

  /// @notice Creates or updates a workflow keyed by `(owner, workflowName, tag)`.
  /// @dev Status and donFamily cannot be changed via this call once a workflow exists.
  /// @param workflowName Human-readable name.
  /// @param tag Unique tag per `(owner, workflowName)`.
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
    WorkflowStatus status,
    string calldata donFamily,
    string calldata binaryUrl,
    string calldata configUrl,
    bytes calldata attributes,
    bool keepAlive
  ) external;

  /// @notice Pauses a workflow owned by the caller.
  /// @param workflowId The workflow identifier.
  function pauseWorkflow(bytes32 workflowId) external;

  /// @notice Pauses multiple workflows owned by the caller.
  /// @param workflowIds The workflow identifiers; must not be empty.
  function batchPauseWorkflows(bytes32[] calldata workflowIds) external;

  /// @notice Activates a paused workflow owned by the caller on `donFamily`.
  /// @param workflowId The workflow identifier.
  /// @param donFamily The target DON family.
  function activateWorkflow(bytes32 workflowId, string calldata donFamily) external;

  /// @notice Activates multiple paused workflows owned by the caller on `donFamily`.
  /// @param workflowIds The workflow identifiers; must not be empty.
  /// @param donFamily The target DON family.
  function batchActivateWorkflows(
    bytes32[] calldata workflowIds,
    string calldata donFamily
  ) external;

  /// @notice Deletes a workflow owned by the caller.
  /// @param workflowId The workflow identifier.
  function deleteWorkflow(bytes32 workflowId) external;

  /// @notice Reassigns the DON family of an active workflow owned by the caller.
  /// @param workflowId The workflow identifier.
  /// @param newDonFamily The new DON family.
  function updateWorkflowDONFamily(bytes32 workflowId, string calldata newDonFamily) external;

  /// @notice Allowlists an off-chain request digest on behalf of the caller.
  /// @param requestDigest The hash of the request payload.
  /// @param expiryTimestamp The timestamp until which the request is valid.
  function allowlistRequest(bytes32 requestDigest, uint32 expiryTimestamp) external;
}
