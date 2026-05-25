// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';

import {Ownable} from 'aave-v4/dependencies/openzeppelin/Ownable.sol';
import {IERC165} from 'openzeppelin-contracts/contracts/utils/introspection/IERC165.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';
import {IRescuable} from 'aave-v4/interfaces/IRescuable.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';

import {FeeSharesMinter} from '../src/FeeSharesMinter.sol';
import {IFeeSharesMinter} from '../src/IFeeSharesMinter.sol';
import {IReceiver} from 'aave-cre/IReceiver.sol';
import {IAaveCREReceiver} from 'aave-cre/IAaveCREReceiver.sol';

import {MockHubHelpers} from './helpers/MockHubHelpers.sol';

contract FeeSharesMinterTest is Test {
  FeeSharesMinter internal minter;

  address internal admin;
  address internal hub;
  uint256 internal constant ASSET_ID = 1;
  uint256 internal constant OTHER_ASSET_ID = 2;
  uint256 internal constant ASSET_COUNT = 5;

  uint16 internal constant HAPPY_THRESHOLD_BPS = 5_00;
  uint256 internal constant HAPPY_ADDED = 1000e18;
  uint256 internal constant HAPPY_FEES = 100e18; // 10% of HAPPY_ADDED — above threshold
  uint256 internal constant HAPPY_PREVIEW_SHARES = 90e18;

  address internal bob;
  address internal anyone;

  function setUp() public {
    admin = makeAddr('admin');
    bob = makeAddr('bob');
    anyone = makeAddr('anyone');
    hub = makeAddr('hub');

    MockHubHelpers.setAssetCount(hub, ASSET_COUNT);

    minter = new FeeSharesMinter(admin);
  }

  function test_supportsInterface() public view {
    assertTrue(minter.supportsInterface(type(IReceiver).interfaceId));
    assertTrue(minter.supportsInterface(type(IAaveCREReceiver).interfaceId));
    assertTrue(minter.supportsInterface(type(IERC165).interfaceId));
    assertFalse(minter.supportsInterface(0xffffffff));
  }

  function test_setConfig_revertsWith_OwnableUnauthorized() public {
    vm.prank(bob);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
    minter.setConfig(hub, ASSET_ID, 100);
  }

  function test_fuzz_setConfig(uint16 minAccruedFeesPercent) public {
    minAccruedFeesPercent = uint16(
      bound(minAccruedFeesPercent, 0, PercentageMath.PERCENTAGE_FACTOR)
    );

    vm.expectEmit(address(minter));
    emit IFeeSharesMinter.ConfigUpdated(hub, ASSET_ID, minAccruedFeesPercent);

    vm.prank(admin);
    minter.setConfig(hub, ASSET_ID, minAccruedFeesPercent);

    assertEq(minter.getConfig(hub, ASSET_ID), minAccruedFeesPercent);
  }

  function test_setConfig_independentPerPair() public {
    vm.startPrank(admin);
    minter.setConfig(hub, ASSET_ID, 100);
    minter.setConfig(hub, OTHER_ASSET_ID, 200);
    vm.stopPrank();

    assertEq(minter.getConfig(hub, ASSET_ID), 100);
    assertEq(minter.getConfig(hub, OTHER_ASSET_ID), 200);
    assertEq(minter.getConfig(hub, 3), 0);
  }

  function test_setConfig_independentPerHub() public {
    address otherHub = makeAddr('otherHub');
    MockHubHelpers.setAssetCount(otherHub, 10);

    vm.startPrank(admin);
    minter.setConfig(hub, ASSET_ID, 100);
    minter.setConfig(otherHub, ASSET_ID, 200);
    vm.stopPrank();

    assertEq(minter.getConfig(hub, ASSET_ID), 100);
    assertEq(minter.getConfig(otherHub, ASSET_ID), 200);
  }

  function test_fuzz_setConfig_revertsWith_InvalidConfig(uint16 minAccruedFeesPercent) public {
    minAccruedFeesPercent = uint16(
      bound(minAccruedFeesPercent, PercentageMath.PERCENTAGE_FACTOR + 1, type(uint16).max)
    );

    vm.prank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(IFeeSharesMinter.InvalidConfig.selector, minAccruedFeesPercent)
    );
    minter.setConfig(hub, ASSET_ID, minAccruedFeesPercent);
  }

  function test_setConfig_revertsWith_AssetNotListed() public {
    vm.prank(admin);
    vm.expectRevert(IHub.AssetNotListed.selector);
    minter.setConfig(hub, ASSET_COUNT, 100);
  }

  function test_canMint_returnsTrue_onHappyPath() public {
    _setupHappyPath();
    _assertCanMint(true);
  }

  function test_canMint_returnsFalse_whenThresholdSetToZero() public {
    _setupHappyPath();
    _assertCanMint(true);

    _setMinPercent(ASSET_ID, 0);
    _assertCanMint(false);
  }

  function test_canMint_returnsFalse_whenAddedAssetsDropToZero() public {
    _setupHappyPath();
    _assertCanMint(true);

    MockHubHelpers.setAddedAssets(hub, ASSET_ID, 0);
    _assertCanMint(false);
  }

  function test_canMint_returnsFalse_whenThresholdRaisedAboveRatio() public {
    _setupHappyPath();
    _assertCanMint(true);

    _setMinPercent(ASSET_ID, 50_00);
    _assertCanMint(false);
  }

  function test_canMint_returnsFalse_whenSharesPreviewRoundsToZero() public {
    _setupHappyPath();
    _assertCanMint(true);

    MockHubHelpers.setPreviewShares(hub, ASSET_ID, HAPPY_FEES, 0);
    _assertCanMint(false);
  }

  function test_checkUpkeep_mirrorsCanMint_andEchoesCheckData() public {
    bytes memory checkData = abi.encode(hub, ASSET_ID);
    (bool upkeepNeeded, bytes memory performData) = minter.checkUpkeep(checkData);
    assertFalse(upkeepNeeded);
    assertEq(performData, checkData);

    _setupHappyPath();

    (upkeepNeeded, performData) = minter.checkUpkeep(checkData);
    assertTrue(upkeepNeeded);
    assertEq(performData, checkData);
  }

  function test_onReport_succeeds_whenAnyoneCalls() public {
    _setupHappyPath();
    MockHubHelpers.expectMintFeeShares(hub, ASSET_ID);

    vm.prank(anyone);
    minter.onReport(_arbitraryMetadata(), abi.encode(hub, ASSET_ID));
  }

  function test_onReport_succeeds_withEmptyMetadata() public {
    _setupHappyPath();
    MockHubHelpers.expectMintFeeShares(hub, ASSET_ID);

    vm.prank(anyone);
    minter.onReport('', abi.encode(hub, ASSET_ID));
  }

  function test_onReport_ignoresMetadataContents() public {
    _setupHappyPath();
    MockHubHelpers.expectMintFeeShares(hub, ASSET_ID);

    bytes memory junk = abi.encodePacked(
      bytes32(uint256(0xdead)),
      bytes10('junk'),
      address(0xBEEF)
    );
    vm.prank(anyone);
    minter.onReport(junk, abi.encode(hub, ASSET_ID));
  }

  function test_onReport_revertsWith_ConditionsNotMet_whenThresholdSetToZero() public {
    _setupHappyPath();
    _assertCanMint(true);

    _setMinPercent(ASSET_ID, 0);

    vm.prank(anyone);
    vm.expectRevert(IFeeSharesMinter.ConditionsNotMet.selector);
    minter.onReport('', abi.encode(hub, ASSET_ID));
  }

  function test_onReport_revertsWith_ConditionsNotMet_whenThresholdRaisedAboveRatio() public {
    _setupHappyPath();
    _assertCanMint(true);

    _setMinPercent(ASSET_ID, 50_00);

    vm.prank(anyone);
    vm.expectRevert(IFeeSharesMinter.ConditionsNotMet.selector);
    minter.onReport('', abi.encode(hub, ASSET_ID));
  }

  function test_rescueToken_onlyOwner() public {
    address token = makeAddr('token');
    vm.mockCall(
      token,
      abi.encodeWithSignature('balanceOf(address)', address(minter)),
      abi.encode(uint256(0))
    );

    vm.prank(bob);
    vm.expectRevert(abi.encodeWithSelector(IRescuable.OnlyRescueGuardian.selector));
    minter.rescueToken(token, bob, 100);
  }

  function test_transferOwnership_2Step() public {
    address newOwner = makeAddr('newOwner');

    vm.prank(admin);
    minter.transferOwnership(newOwner);

    assertEq(minter.owner(), admin);
    assertEq(minter.pendingOwner(), newOwner);

    vm.prank(newOwner);
    minter.acceptOwnership();

    assertEq(minter.owner(), newOwner);
    assertEq(minter.pendingOwner(), address(0));
  }

  function _setMinPercent(uint256 assetId, uint16 percent) internal {
    vm.prank(admin);
    minter.setConfig(hub, assetId, percent);
  }

  function _setupHappyPath() internal {
    _setMinPercent(ASSET_ID, HAPPY_THRESHOLD_BPS);
    MockHubHelpers.setAddedAssets(hub, ASSET_ID, HAPPY_ADDED);
    MockHubHelpers.setAccruedFees(hub, ASSET_ID, HAPPY_FEES);
    MockHubHelpers.setPreviewShares(hub, ASSET_ID, HAPPY_FEES, HAPPY_PREVIEW_SHARES);
  }

  function _assertCanMint(bool expected) internal view {
    assertEq(minter.canMint(hub, ASSET_ID), expected);
  }

  function _arbitraryMetadata() internal pure returns (bytes memory) {
    return abi.encodePacked(bytes32(uint256(1)), bytes10('any-name'), address(0xCAFE));
  }
}
