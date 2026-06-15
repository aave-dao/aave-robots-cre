// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWorkflowRegistry} from 'aave-cre/IWorkflowRegistry.sol';

contract MockWorkflowRegistry is IWorkflowRegistry {
  struct Workflow {
    address owner;
    bytes32 workflowId;
    WorkflowStatus status;
    bytes32 donHash;
    bool exists;
  }

  mapping(bytes32 rid => Workflow) internal _workflows;
  mapping(bytes32 workflowId => bytes32 rid) internal _idToRid;
  mapping(address owner => bool) public linked;
  mapping(bytes32 donHash => uint32 limit) public donLimit;
  mapping(bytes32 donHash => uint32 active) public donActiveCount;
  mapping(bytes32 ownerDigest => uint32 expiry) public allowlistedRequests;

  error OwnershipLinkDoesNotExist(address owner);
  error ZeroWorkflowIDNotAllowed();
  error WorkflowIDAlreadyExists(bytes32 workflowId);
  error BinaryURLRequired();
  error WorkflowNameRequired();
  error WorkflowTagRequired();
  error WorkflowDoesNotExist();
  error CallerIsNotWorkflowOwner(address caller);
  error DonLimitNotSet(string donFamily);
  error MaxWorkflowsPerDONExceeded(string donFamily);
  error CannotChangeStatusOnUpdate(WorkflowStatus attempted);
  error CannotChangeDONFamilyOnUpdate(string attempted);
  error CannotUpdateDONFamilyForPausedWorkflows();
  error EmptyUpdateBatch();
  error InvalidExpiryTimestamp();

  function setDONLimit(string calldata donFamily, uint32 limit) external {
    donLimit[_hash(donFamily)] = limit;
  }

  function isLinked(address owner) external view returns (bool) {
    return linked[owner];
  }

  function getWorkflow(bytes32 workflowId) external view returns (Workflow memory) {
    return _workflows[_idToRid[workflowId]];
  }

  function linkOwner(uint256, bytes32, bytes calldata) external {
    linked[msg.sender] = true;
  }

  function upsertWorkflow(
    string calldata workflowName,
    string calldata tag,
    bytes32 workflowId,
    WorkflowStatus status,
    string calldata donFamily,
    string calldata binaryUrl,
    string calldata,
    bytes calldata,
    bool
  ) external {
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    require(workflowId != bytes32(0), ZeroWorkflowIDNotAllowed());
    require(bytes(binaryUrl).length > 0, BinaryURLRequired());
    require(bytes(workflowName).length > 0, WorkflowNameRequired());
    require(bytes(tag).length > 0, WorkflowTagRequired());

    bytes32 rid = keccak256(abi.encode(msg.sender, workflowName, tag));
    Workflow storage wf = _workflows[rid];
    bytes32 donHash = _hash(donFamily);

    if (!wf.exists) {
      require(_idToRid[workflowId] == bytes32(0), WorkflowIDAlreadyExists(workflowId));
      if (status == WorkflowStatus.ACTIVE) {
        _enforceLimit(donHash, donFamily);
        donActiveCount[donHash] += 1;
      }
      _workflows[rid] = Workflow({
        owner: msg.sender,
        workflowId: workflowId,
        status: status,
        donHash: donHash,
        exists: true
      });
      _idToRid[workflowId] = rid;
    } else {
      require(wf.owner == msg.sender, CallerIsNotWorkflowOwner(msg.sender));
      require(wf.status == status, CannotChangeStatusOnUpdate(status));
      require(wf.donHash == donHash, CannotChangeDONFamilyOnUpdate(donFamily));
      require(_idToRid[workflowId] == bytes32(0), WorkflowIDAlreadyExists(workflowId));
      delete _idToRid[wf.workflowId];
      wf.workflowId = workflowId;
      _idToRid[workflowId] = rid;
    }
  }

  function pauseWorkflow(bytes32 workflowId) public {
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    Workflow storage wf = _getRecord(workflowId);
    if (wf.status != WorkflowStatus.PAUSED) {
      wf.status = WorkflowStatus.PAUSED;
      donActiveCount[wf.donHash] -= 1;
    }
  }

  function batchPauseWorkflows(bytes32[] calldata workflowIds) external {
    require(workflowIds.length > 0, EmptyUpdateBatch());
    for (uint256 i = 0; i < workflowIds.length; i++) {
      pauseWorkflow(workflowIds[i]);
    }
  }

  function activateWorkflow(bytes32 workflowId, string calldata donFamily) public {
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    Workflow storage wf = _getRecord(workflowId);
    if (wf.status != WorkflowStatus.ACTIVE) {
      bytes32 donHash = _hash(donFamily);
      _enforceLimit(donHash, donFamily);
      wf.status = WorkflowStatus.ACTIVE;
      wf.donHash = donHash;
      donActiveCount[donHash] += 1;
    }
  }

  function batchActivateWorkflows(
    bytes32[] calldata workflowIds,
    string calldata donFamily
  ) external {
    require(workflowIds.length > 0, EmptyUpdateBatch());
    for (uint256 i = 0; i < workflowIds.length; i++) {
      activateWorkflow(workflowIds[i], donFamily);
    }
  }

  function deleteWorkflow(bytes32 workflowId) external {
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    bytes32 rid = _idToRid[workflowId];
    Workflow storage wf = _workflows[rid];
    require(wf.exists, WorkflowDoesNotExist());
    require(wf.owner == msg.sender, CallerIsNotWorkflowOwner(msg.sender));
    if (wf.status == WorkflowStatus.ACTIVE) {
      donActiveCount[wf.donHash] -= 1;
    }
    delete _idToRid[workflowId];
    delete _workflows[rid];
  }

  function updateWorkflowDONFamily(bytes32 workflowId, string calldata newDonFamily) external {
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    Workflow storage wf = _getRecord(workflowId);
    require(wf.status == WorkflowStatus.ACTIVE, CannotUpdateDONFamilyForPausedWorkflows());
    bytes32 newDonHash = _hash(newDonFamily);
    if (wf.donHash == newDonHash) return;
    _enforceLimit(newDonHash, newDonFamily);
    donActiveCount[wf.donHash] -= 1;
    donActiveCount[newDonHash] += 1;
    wf.donHash = newDonHash;
  }

  function allowlistRequest(bytes32 requestDigest, uint32 expiryTimestamp) external {
    require(expiryTimestamp > block.timestamp, InvalidExpiryTimestamp());
    require(linked[msg.sender], OwnershipLinkDoesNotExist(msg.sender));
    allowlistedRequests[keccak256(abi.encode(msg.sender, requestDigest))] = expiryTimestamp;
  }

  function _getRecord(bytes32 workflowId) internal view returns (Workflow storage wf) {
    wf = _workflows[_idToRid[workflowId]];
    require(wf.exists, WorkflowDoesNotExist());
    require(wf.owner == msg.sender, CallerIsNotWorkflowOwner(msg.sender));
  }

  function _enforceLimit(bytes32 donHash, string calldata donFamily) internal view {
    require(donLimit[donHash] != 0, DonLimitNotSet(donFamily));
    require(
      donActiveCount[donHash] + 1 <= donLimit[donHash],
      MaxWorkflowsPerDONExceeded(donFamily)
    );
  }

  function _hash(string calldata str) internal pure returns (bytes32) {
    return keccak256(bytes(str));
  }
}
