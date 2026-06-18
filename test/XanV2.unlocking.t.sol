// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {MockXanV2} from "./mocks/XanV2.m.sol";

contract XanV2UnlockingTest is Test {
    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;
    address internal _defaultSender;
    address internal immutable _OTHER = makeAddr("other");
    address internal immutable _GOVERNANCE_COUNCIL = makeAddr("governanceCouncil");

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy proxy and mint tokens for the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _GOVERNANCE_COUNCIL))
            })
        );

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        _xanV2Impl = address(new MockXanV2(_xanV1Proxy.implementation()));

        _winUpgradeVoteForV2Impl(_xanV1Proxy);

        skip(Parameters.DELAY_DURATION);

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy),
            newImpl: _xanV2Impl,
            data: abi.encodeCall(XanV2.reinitializeFromV1, (msg.sender))
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    function test_full_principal_locked_at_start() public {
        // `_defaultSender` locked the entire supply in V1 before the upgrade.
        vm.warp(Parameters.VESTING_START);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);
    }

    function test_unlock_reverts_when_nothing_vested() public {
        vm.warp(Parameters.VESTING_START);
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _defaultSender));
        _xanV2Proxy.unlock();
    }

    function test_vesting_is_linear() public {
        vm.warp(Parameters.VESTING_START + Parameters.VESTING_DURATION / 2);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY / 2);

        // Vesting does not become spendable until it is unlocked.
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);
    }

    function test_unlock_makes_vested_tokens_spendable() public {
        vm.warp(Parameters.VESTING_START + Parameters.VESTING_DURATION / 2);

        vm.prank(_defaultSender);
        uint256 value = _xanV2Proxy.unlock();
        assertEq(value, Parameters.SUPPLY / 2);

        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);

        // The unlocked tokens can now be transferred; the still-locked ones cannot.
        vm.prank(_defaultSender);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_OTHER, Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.balanceOf(_OTHER), Parameters.SUPPLY / 2);

        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_OTHER, 1);
    }

    function test_fully_vested_after_duration() public {
        vm.warp(Parameters.VESTING_START + Parameters.VESTING_DURATION);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY);

        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
    }

    function test_vestingStart_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingStart(), Parameters.VESTING_START);
    }

    function test_vestingEnd_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingEnd(), Parameters.VESTING_START + Parameters.VESTING_DURATION);
    }

    function _winUpgradeVoteForV2Impl(XanV1 xanV1Proxy) internal {
        vm.startPrank(_defaultSender);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_defaultSender));
        xanV1Proxy.castVote(_xanV2Impl);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();
        skip(Parameters.DELAY_DURATION);
    }
}
