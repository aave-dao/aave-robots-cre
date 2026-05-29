// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockHub {
  event MintFeeShares(
    uint256 indexed assetId,
    address indexed feeReceiver,
    uint256 shares,
    uint256 assets
  );

  error MintNotAllowed(uint256 assetId);
  error AssetNotListed();

  uint256 internal constant FIXED_FEES = 100e18;
  uint256 internal constant FIXED_ADDED = 1000e18;

  uint256 internal _assetCount;
  mapping(uint256 => bool) internal _canMint;

  function setAssetCount(uint256 count) external {
    _assetCount = count;
  }

  function setCanMint(uint256 assetId, bool allowed) external {
    _canMint[assetId] = allowed;
  }

  function getAssetCount() external view returns (uint256) {
    return _assetCount;
  }

  function getAssetAccruedFees(uint256) external pure returns (uint256) {
    return FIXED_FEES;
  }

  function getAddedAssets(uint256) external pure returns (uint256) {
    return FIXED_ADDED;
  }

  function previewAddByAssets(uint256, uint256 assets) external pure returns (uint256) {
    return assets;
  }

  function mintFeeShares(uint256 assetId) external returns (uint256) {
    require(assetId < _assetCount, AssetNotListed());
    require(_canMint[assetId], MintNotAllowed(assetId));
    uint256 r = uint256(keccak256(abi.encode(assetId, block.number, block.timestamp)));
    emit MintFeeShares(assetId, address(this), r, r ^ 0xdeadbeef);
    return r;
  }
}
