// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from 'aave-v4/dependencies/openzeppelin/Ownable2Step.sol';
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
contract FeeSharesMinter is IFeeSharesMinter, Ownable2Step, Rescuable {
  using PercentageMath for uint256;

  mapping(address hub => mapping(uint256 assetId => uint16)) internal _minAccruedFeesPercent;

  /// @dev Constructor.
  /// @param initialOwner_ The address of the initial owner.
  constructor(address initialOwner_) Ownable(initialOwner_) {}

  /// @inheritdoc IFeeSharesMinter
  function setConfig(
    address hub,
    uint256 assetId,
    uint16 minAccruedFeesPercent
  ) external onlyOwner {
    require(
      minAccruedFeesPercent <= PercentageMath.PERCENTAGE_FACTOR,
      InvalidConfig(minAccruedFeesPercent)
    );
    require(assetId < IHub(hub).getAssetCount(), IHub.AssetNotListed());
    _minAccruedFeesPercent[hub][assetId] = minAccruedFeesPercent;
    emit ConfigUpdated(hub, assetId, minAccruedFeesPercent);
  }

  /// @inheritdoc IReceiver
  /// @dev `onReport` is permissionless: both `metadata` and `msg.sender` are
  /// ignored. The action (`IHub.mintFeeShares`) is already gated by the owner's
  /// per-asset threshold, the hub's role check, and the round-to-non-zero guard
  /// in `_canMint`.
  function onReport(bytes calldata /* metadata */, bytes calldata report) external override {
    (address hub, uint256 assetId) = abi.decode(report, (address, uint256));
    require(_canMint(hub, assetId), ConditionsNotMet());
    IHub(hub).mintFeeShares(assetId);
  }

  /// @inheritdoc IAaveCREReceiver
  function checkUpkeep(
    bytes calldata checkData
  ) external view returns (bool upkeepNeeded, bytes memory performData) {
    (address hub, uint256 assetId) = abi.decode(checkData, (address, uint256));
    upkeepNeeded = _canMint(hub, assetId);
    performData = checkData;
  }

  /// @inheritdoc IFeeSharesMinter
  function getConfig(address hub, uint256 assetId) external view returns (uint16) {
    return _minAccruedFeesPercent[hub][assetId];
  }

  /// @inheritdoc IFeeSharesMinter
  function canMint(address hub, uint256 assetId) external view returns (bool) {
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
    if (minAccruedFeesPercent == 0) return false;

    IHub targetHub = IHub(hub);
    uint256 accruedFees = targetHub.getAssetAccruedFees(assetId);
    uint256 totalAddedAssets = targetHub.getAddedAssets(assetId);

    if (totalAddedAssets == 0) return false;
    if (accruedFees.percentDivDown(totalAddedAssets) < minAccruedFeesPercent) return false;

    return targetHub.previewAddByAssets(assetId, accruedFees) > 0;
  }

  /// @inheritdoc Rescuable
  function _rescueGuardian() internal view override returns (address) {
    return owner();
  }
}
