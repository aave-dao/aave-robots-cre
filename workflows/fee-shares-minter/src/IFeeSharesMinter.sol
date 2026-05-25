// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAaveCREReceiver} from 'aave-cre/IAaveCREReceiver.sol';

/// @title IFeeSharesMinter
/// @notice Robot that mints accrued fee shares on Aave v4 Hubs once an
/// owner-configured per-(hub, asset) ratio is crossed. `report` for `onReport`
/// and `checkData` for `checkUpkeep` are both `abi.encode(address hub, uint256 assetId)`.
interface IFeeSharesMinter is IAaveCREReceiver {
  /// @notice Emitted when the mint threshold for a (hub, asset) pair is updated.
  /// @param hub Hub the threshold applies to.
  /// @param assetId Asset identifier within `hub`.
  /// @param minAccruedFeesPercent New threshold in BPS.
  event ConfigUpdated(address indexed hub, uint256 indexed assetId, uint16 minAccruedFeesPercent);

  /// @notice Thrown when `onReport` runs but the mint conditions are not met.
  error ConditionsNotMet();

  /// @notice Thrown when `setConfig` is called with a value above `PercentageMath.PERCENTAGE_FACTOR`.
  /// @param minAccruedFeesPercent Rejected value.
  error InvalidConfig(uint16 minAccruedFeesPercent);

  /// @notice Set the mint threshold for a (hub, asset) pair. Owner-only.
  /// @param hub Hub the threshold applies to.
  /// @param assetId Asset identifier within `hub`. Must be listed on the hub.
  /// @param minAccruedFeesPercent Threshold in BPS, capped at `PercentageMath.PERCENTAGE_FACTOR`. 0 disables minting.
  function setConfig(address hub, uint256 assetId, uint16 minAccruedFeesPercent) external;

  /// @notice Returns the configured mint threshold for a (hub, asset) pair, in BPS.
  /// @param hub Hub the threshold applies to.
  /// @param assetId Asset identifier within `hub`.
  function getConfig(address hub, uint256 assetId) external view returns (uint16);

  /// @notice Returns whether `onReport` would mint fee shares for a (hub, asset) pair.
  /// @param hub Hub to evaluate against.
  /// @param assetId Asset identifier within `hub`.
  function canMint(address hub, uint256 assetId) external view returns (bool);
}
