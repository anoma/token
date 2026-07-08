// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Fixture} from "./fixtures/XanV2Fixture.sol";

contract XanV2VotingTest is XanV2Fixture {
    using SafeERC20 for XanV2;

    address internal immutable _OTHER = makeAddr("other");

    function test_getPastVotes_returns_the_checkpointed_value() public {
        vm.warp(100);
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);

        vm.warp(101);
        assertEq(_xanV2Proxy.getPastVotes(_defaultSender, 100), Parameters.SUPPLY);
    }

    function test_getPastTotalSupply_reverts_during_the_upgrade() public {
        assertEq(Time.timestamp(), _upgradeTimestamp);
        vm.expectRevert(
            abi.encodeWithSelector(VotesUpgradeable.ERC5805FutureLookup.selector, _upgradeTimestamp, _upgradeTimestamp),
            address(_xanV2Proxy)
        );
        _xanV2Proxy.getPastTotalSupply(_upgradeTimestamp);
    }

    function test_getPastTotalSupply_returns_the_seeded_supply_after_upgrade() public {
        // The checkpoint is seeded at the upgrade; step one second past it so the upgrade instant is a valid past
        // timepoint, then read it back.
        vm.warp(_upgradeTimestamp + 1);
        assertEq(_xanV2Proxy.getPastTotalSupply(_upgradeTimestamp), Parameters.SUPPLY);
    }

    function test_transfer_moves_voting_power_between_delegates() public {
        vm.warp(_vestingEnd);

        // Self-delegate as `_defaultSender`.
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);

        // Self-delegate as `_OTHER`.
        vm.prank(_OTHER);
        _xanV2Proxy.delegate(_OTHER);
        assertEq(_xanV2Proxy.getVotes(_OTHER), 0);

        // Transfer 1/3  to `_OTHER`.
        uint256 oneThird = Parameters.SUPPLY / 3;

        vm.startPrank(_defaultSender);
        _xanV2Proxy.unlock();
        _xanV2Proxy.safeTransfer(_OTHER, oneThird);
        vm.stopPrank();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY - oneThird);
        assertEq(_xanV2Proxy.getVotes(_OTHER), oneThird);
    }

    function test_delegate_grants_voting_power_equal_to_balance() public {
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);

        // Voting power tracks the full balance, including the still-locked (unvested) tokens.
        assertEq(_xanV2Proxy.getVotes(_defaultSender), _xanV2Proxy.balanceOf(_defaultSender));
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_locked_tokens_before_vesting_starts() public {
        vm.warp(_vestingStart - 1);

        // The clock is before the vesting period.
        assertLt(Time.timestamp(), _vestingStart);

        // Nothing has vested, so nothing is unlockable and the whole balance is still locked.
        assertEq(_xanV2Proxy.unlockableBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_vested_but_not_unlocked_tokens_during_vesting() public {
        vm.warp(_vestingMid);

        // The clock is inside the vesting period.
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);

        // Half has vested and is unlockable, but nothing has been unlocked: the full balance is still locked.
        assertEq(_xanV2Proxy.unlockableBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_partially_unlocked_tokens_during_vesting() public {
        vm.warp(_vestingMid);

        // The clock is inside the vesting period.
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);

        // Unlock the vested half: tokens move from locked to unlocked, but the balance is unchanged.
        _unlock();
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.unlockableBalanceOf(_defaultSender), 0);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_vested_but_not_unlocked_tokens_after_vesting() public {
        vm.warp(_vestingEnd + 1);

        // The clock is after the vesting period.
        assertGt(Time.timestamp(), _vestingEnd);

        // Everything has vested and is unlockable, but nothing has been unlocked: the full balance is still locked.
        assertEq(_xanV2Proxy.unlockableBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_fully_unlocked_tokens_after_vesting() public {
        vm.warp(_vestingEnd + 1);

        // The clock is after the vesting period.
        assertGt(Time.timestamp(), _vestingEnd);

        // Unlock everything: the entire balance is now unlocked, nothing is locked.
        _unlock();
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.unlockableBalanceOf(_defaultSender), 0);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_is_unchanged_by_unlocking_across_vesting() public {
        _selfDelegate();

        // Before the vesting period: nothing to unlock yet.
        vm.warp(_vestingStart - 1);
        assertLt(Time.timestamp(), _vestingStart);
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);

        // During the vesting period: unlock the vested half.
        vm.warp(_vestingMid);
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);
        _unlock();
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);

        // After the vesting period: unlock the remainder.
        vm.warp(_vestingEnd + 1);
        assertGt(Time.timestamp(), _vestingEnd);
        _unlock();
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_returns_zero_before_delegation() public view {
        assertEq(_xanV2Proxy.getVotes(_defaultSender), 0);
    }

    function test_getPastTotalSupply_is_zero_before_the_upgrade() public view {
        assertEq(Time.timestamp(), _upgradeTimestamp);
        assertEq(_xanV2Proxy.getPastTotalSupply(_upgradeTimestamp - 1), 0);
    }

    function test_clock_tracks_the_block_timestamp() public view {
        assertEq(_xanV2Proxy.clock(), uint48(block.timestamp));
    }

    function test_CLOCK_MODE_returns_the_timestamp_mode() public view {
        assertEq(_xanV2Proxy.CLOCK_MODE(), "mode=timestamp");
    }

    function _selfDelegate() internal {
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);
    }

    /// @notice Unlocks all of `_defaultSender`'s currently vested tokens.
    function _unlock() internal {
        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();
    }
}
