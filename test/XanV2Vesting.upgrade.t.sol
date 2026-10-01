// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {XanV2Vesting} from "../src/XanV2Vesting.sol";
import {XanV2VestingFixture} from "./fixtures/XanV2VestingFixture.sol";

contract XanV2VestingUpgradeTest is XanV2VestingFixture {
    address internal immutable _OTHER = makeAddr("other");

    function test_upgradeToAndCall_reverts_if_the_caller_is_not_the_owner() public {
        address newImpl = address(new XanV2Vesting(_xan));

        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _OTHER), address(_vesting)
        );
        _vesting.upgradeToAndCall(newImpl, "");
    }

    function test_upgradeToAndCall_upgrades_if_the_caller_is_the_owner() public {
        address newImpl = address(new XanV2Vesting(_xan));

        vm.prank(_vesting.owner());
        _vesting.upgradeToAndCall(newImpl, "");

        assertEq(UnsafeUpgrades.getImplementationAddress(address(_vesting)), newImpl);
    }

    function test_upgradeToAndCall_keeps_the_principals_and_the_unlocked_amounts() public {
        deal(address(_xan), address(_vesting), _vesting.totalPrincipal());
        vm.warp(_vestingMid);
        _unlockAll();

        address owner = _vesting.owner();
        uint256 unlockedByAlice = _vesting.unlockedAmountOf(_ALICE);
        uint256 lockedTotal = _vesting.totalLockedBalance();

        address newImpl = address(new XanV2Vesting(_xan));
        vm.prank(owner);
        _vesting.upgradeToAndCall(newImpl, "");

        assertEq(_vesting.owner(), owner);
        assertEq(_vesting.principalOf(_ALICE), _PRINCIPAL);
        assertEq(_vesting.unlockedAmountOf(_ALICE), unlockedByAlice);
        assertEq(_vesting.totalPrincipal(), _PRINCIPAL + _PRINCIPAL / 3);
        assertEq(_vesting.totalLockedBalance(), lockedTotal);
        assertEq(_vesting.getRecipients().length, 2);
    }
}
