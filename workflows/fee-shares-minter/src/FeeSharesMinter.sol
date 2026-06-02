// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {OwnableWithGuardian} from 'solidity-utils/contracts/access-control/OwnableWithGuardian.sol';
import {IERC165} from 'openzeppelin-contracts/contracts/utils/introspection/IERC165.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';
import {Rescuable} from 'aave-v4/utils/Rescuable.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {IReceiver} from 'aave-cre/IReceiver.sol';
import {IAaveCREReceiver} from 'aave-cre/IAaveCREReceiver.sol';
import {IFeeSharesMinter} from './IFeeSharesMinter.sol';

/// @title FeeSharesMinter
/// @author Aave Labs
/// @notice Receives reports from the CRE workflow and mints fee shares on the hub when the configured threshold is crossed.
contract FeeSharesMinter is IFeeSharesMinter, OwnableWithGuardian, Rescuable {
  using PercentageMath for uint256;

  /// @inheritdoc IFeeSharesMinter
  uint16 public constant override DISABLED_THRESHOLD = type(uint16).max;

  mapping(address hub => mapping(uint256 assetId => uint16)) internal _minAccruedFeesPercent;

  /// @dev Constructor.
  /// @param initialOwner_ The address of the initial owner.
  /// @param initialGuardian_ The address of the initial guardian.
  constructor(
    address initialOwner_,
    address initialGuardian_
  ) OwnableWithGuardian(initialOwner_, initialGuardian_) {}

  /// @inheritdoc IFeeSharesMinter
  function setConfig(
    address hub,
    uint256 assetId,
    uint16 minAccruedFeesPercent
  ) external onlyOwner {
    require(_isActiveThreshold(minAccruedFeesPercent), InvalidConfig(minAccruedFeesPercent));
    require(assetId < IHub(hub).getAssetCount(), IHub.AssetNotListed());
    _minAccruedFeesPercent[hub][assetId] = minAccruedFeesPercent;
    emit ConfigUpdated(hub, assetId, minAccruedFeesPercent);
  }

  /// @inheritdoc IFeeSharesMinter
  function disableMinting(address hub, uint256 assetId) external onlyOwnerOrGuardian {
    _minAccruedFeesPercent[hub][assetId] = DISABLED_THRESHOLD;
    emit ConfigUpdated(hub, assetId, DISABLED_THRESHOLD);
  }

  /// @inheritdoc IReceiver
  /// @dev `onReport` is permissionless: both `metadata` and `msg.sender` are
  /// ignored. The action (`IHub.mintFeeShares`) is already gated by the owner's
  /// per-asset threshold, the hub's role check, and the round-to-non-zero guard
  /// in `_canMint`.
  function onReport(bytes calldata /* metadata */, bytes calldata report) external override {
    HubAssetPair[] memory pairs = abi.decode(report, (HubAssetPair[]));
    uint256 minted = 0;
    for (uint256 i = 0; i < pairs.length; i++) {
      if (!_canMint(pairs[i].hub, pairs[i].assetId)) continue;
      IHub(pairs[i].hub).mintFeeShares(pairs[i].assetId);
      minted++;
    }
    require(minted > 0, ConditionsNotMet());
  }

  /// @inheritdoc IAaveCREReceiver
  function checkUpkeep(
    bytes calldata checkData
  ) external view returns (bool upkeepNeeded, bytes memory performData) {
    HubAssetPair[] memory pairs = abi.decode(checkData, (HubAssetPair[]));
    HubAssetPair[] memory buffer = new HubAssetPair[](pairs.length);
    uint256 count = 0;
    for (uint256 i = 0; i < pairs.length; i++) {
      if (_canMint(pairs[i].hub, pairs[i].assetId)) {
        buffer[count++] = pairs[i];
      }
    }
    HubAssetPair[] memory mintable = new HubAssetPair[](count);
    for (uint256 i = 0; i < count; i++) mintable[i] = buffer[i];
    return (count > 0, abi.encode(mintable));
  }

  /// @inheritdoc IFeeSharesMinter
  function getConfig(address hub, uint256 assetId) external view returns (uint16) {
    return _minAccruedFeesPercent[hub][assetId];
  }

  /// @inheritdoc IFeeSharesMinter
  function canMint(address hub, uint256 assetId) external view returns (bool) {
    require(_minAccruedFeesPercent[hub][assetId] != 0, NotConfigured(hub, assetId));
    return _canMint(hub, assetId);
  }

  /// @inheritdoc IERC165
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return
      interfaceId == type(IReceiver).interfaceId ||
      interfaceId == type(IAaveCREReceiver).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  function _canMint(address hub, uint256 assetId) internal view virtual returns (bool) {
    uint16 minAccruedFeesPercent = _minAccruedFeesPercent[hub][assetId];
    if (!_isActiveThreshold(minAccruedFeesPercent)) return false;

    IHub targetHub = IHub(hub);
    uint256 accruedFees = targetHub.getAssetAccruedFees(assetId);
    uint256 totalAddedAssets = targetHub.getAddedAssets(assetId);

    if (totalAddedAssets == 0) return false;
    if (accruedFees.percentDivDown(totalAddedAssets) < minAccruedFeesPercent) return false;

    return targetHub.previewAddByAssets(assetId, accruedFees) > 0;
  }

  function _isActiveThreshold(uint16 minAccruedFeesPercent) internal pure returns (bool) {
    return minAccruedFeesPercent > 0 && minAccruedFeesPercent <= PercentageMath.PERCENTAGE_FACTOR;
  }

  /// @inheritdoc Rescuable
  function _rescueGuardian() internal view override returns (address) {
    return owner();
  }
}
