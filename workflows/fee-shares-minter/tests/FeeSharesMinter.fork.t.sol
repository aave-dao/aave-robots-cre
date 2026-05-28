// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {IAccessManagerEnumerable} from 'aave-v4/access/interfaces/IAccessManagerEnumerable.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';
import {Roles} from 'aave-v4/deployments/utils/libraries/Roles.sol';
import {AaveV4Ethereum, AaveV4EthereumHubs} from 'aave-address-book/AaveV4Ethereum.sol';

import {FeeSharesMinter} from '../src/FeeSharesMinter.sol';
import {IFeeSharesMinter} from '../src/IFeeSharesMinter.sol';

contract FeeSharesMinterForkTest is Test {
  using PercentageMath for uint256;

  FeeSharesMinter internal minter;
  address internal owner = makeAddr('fork-owner');
  address internal guardian = makeAddr('fork-guardian');
  address internal anyone = makeAddr('fork-anyone');

  IHub internal hub;
  IAccessManagerEnumerable internal accessManager;

  function setUp() public {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
    }
    vm.createSelectFork(rpc);

    hub = AaveV4EthereumHubs.CORE_HUB;
    accessManager = AaveV4Ethereum.ACCESS_MANAGER;

    minter = new FeeSharesMinter(owner, guardian);

    address defaultAdmin = accessManager.getRoleMember(Roles.ACCESS_MANAGER_ADMIN_ROLE, 0);
    vm.prank(defaultAdmin);
    accessManager.grantRole(Roles.HUB_FEE_MINTER_ROLE, address(minter), 0);

    (bool isMember, ) = accessManager.hasRole(Roles.HUB_FEE_MINTER_ROLE, address(minter));
    assertTrue(isMember);
  }

  function test_fork_setConfig_acceptsRealAssetIds() public {
    assertGt(hub.getAssetCount(), 0);

    vm.expectEmit(address(minter));
    emit IFeeSharesMinter.ConfigUpdated(address(hub), 0, 1);

    vm.prank(owner);
    minter.setConfig(address(hub), 0, 1);
    assertEq(minter.getConfig(address(hub), 0), 1);
  }

  function test_fork_disableMinting_byGuardian() public {
    vm.prank(owner);
    minter.setConfig(address(hub), 0, 1);
    assertEq(minter.getConfig(address(hub), 0), 1);

    vm.expectEmit(address(minter));
    emit IFeeSharesMinter.ConfigUpdated(address(hub), 0, 0);

    vm.prank(guardian);
    minter.disableMinting(address(hub), 0);
    assertEq(minter.getConfig(address(hub), 0), 0);
  }

  function test_fork_setConfig_revertsForUnlistedAsset() public {
    uint256 assetCount = hub.getAssetCount();
    vm.prank(owner);
    vm.expectRevert(IHub.AssetNotListed.selector);
    minter.setConfig(address(hub), assetCount, 1);
  }

  function test_fork_onReport_revertsWith_ConditionsNotMet_whenUnconfigured() public {
    uint256 assetId = 0;
    assertFalse(minter.canMint(address(hub), assetId));

    vm.prank(anyone);
    vm.expectRevert(IFeeSharesMinter.ConditionsNotMet.selector);
    minter.onReport('', abi.encode(address(hub), assetId));
  }

  function test_fork_onReport_succeeds_permissionlessly_whenMintable() public {
    (bool found, uint256 assetId, uint16 threshold) = _findMintableAsset();
    if (!found) {
      vm.skip(true);
    }

    vm.prank(owner);
    minter.setConfig(address(hub), assetId, threshold);

    assertTrue(minter.canMint(address(hub), assetId));
    (bool upkeepNeeded, bytes memory performData) = minter.checkUpkeep(
      abi.encode(address(hub), assetId)
    );
    assertTrue(upkeepNeeded);
    assertEq(performData, abi.encode(address(hub), assetId));

    uint256 expectedFees = hub.getAssetAccruedFees(assetId);
    uint256 expectedShares = hub.previewAddByAssets(assetId, expectedFees);
    address expectedFeeReceiver = hub.getAssetConfig(assetId).feeReceiver;

    vm.expectEmit(address(hub));
    emit IHub.MintFeeShares(assetId, expectedFeeReceiver, expectedShares, expectedFees);

    vm.prank(anyone);
    minter.onReport('', abi.encode(address(hub), assetId));

    assertFalse(minter.canMint(address(hub), assetId));
  }

  function _findMintableAsset()
    internal
    view
    returns (bool found, uint256 assetId, uint16 threshold)
  {
    uint256 assetCount = hub.getAssetCount();
    for (uint256 i = 0; i < assetCount; i++) {
      uint256 added = hub.getAddedAssets(i);
      if (added == 0) continue;
      uint256 fees = hub.getAssetAccruedFees(i);
      if (fees == 0) continue;
      if (hub.previewAddByAssets(i, fees) == 0) continue;

      uint256 ratio = fees.percentDivDown(added);
      if (ratio == 0) continue;
      uint256 t = ratio > PercentageMath.PERCENTAGE_FACTOR
        ? PercentageMath.PERCENTAGE_FACTOR
        : ratio;
      return (true, i, uint16(t));
    }
    return (false, 0, 0);
  }
}
