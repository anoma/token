// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

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

    function test_getPastTotalSupply_returns_the_seeded_supply_after_upgrade() public {
        // The V1 supply predates `ERC20Votes`; the upgrade seeds the voting total-supply checkpoint so quorum is
        // not zero. It becomes queryable once it is in the past (here, after the upgrade timestamp).
        vm.warp(_vestingStart);
        assertEq(_xanV2Proxy.getPastTotalSupply(_vestingStart - 1), Parameters.SUPPLY);
    }

    function test_transfer_moves_voting_power_between_delegates() public {
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);
        vm.prank(_OTHER);
        _xanV2Proxy.delegate(_OTHER);

        // Half-way through vesting, unlock the vested half and transfer it to `_OTHER`.
        vm.warp(_vestingMid);
        vm.startPrank(_defaultSender);
        _xanV2Proxy.unlock();
        _xanV2Proxy.safeTransfer(_OTHER, Parameters.SUPPLY / 2);
        vm.stopPrank();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.getVotes(_OTHER), Parameters.SUPPLY / 2);
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

        // Nothing has vested, so nothing is claimable and the whole balance is still locked.
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_vested_unclaimed_tokens_during_vesting() public {
        vm.warp(_vestingMid);

        // The clock is inside the vesting period.
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);

        // Half has vested and is claimable, but nothing has been claimed: the full balance is still locked.
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_partially_claimed_tokens_during_vesting() public {
        vm.warp(_vestingMid);

        // The clock is inside the vesting period.
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);

        // Claim the vested half: tokens move from locked to unlocked, but the balance is unchanged.
        _unlock();
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_vested_unclaimed_tokens_after_vesting() public {
        vm.warp(_vestingEnd + 1);

        // The clock is after the vesting period.
        assertGt(Time.timestamp(), _vestingEnd);

        // Everything has vested and is claimable, but nothing has been claimed: the full balance is still locked.
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_counts_fully_claimed_tokens_after_vesting() public {
        vm.warp(_vestingEnd + 1);

        // The clock is after the vesting period.
        assertGt(Time.timestamp(), _vestingEnd);

        // Claim everything: the entire balance is now unlocked, nothing is locked.
        _unlock();
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);

        _selfDelegate();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_is_unchanged_by_claiming_across_vesting() public {
        _selfDelegate();

        // Before the vesting period: nothing to claim yet.
        vm.warp(_vestingStart - 1);
        assertLt(Time.timestamp(), _vestingStart);
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);

        // During the vesting period: claim the vested half.
        vm.warp(_vestingMid);
        assertGe(Time.timestamp(), _vestingStart);
        assertLt(Time.timestamp(), _vestingEnd);
        _unlock();
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);

        // After the vesting period: claim the remainder.
        vm.warp(_vestingEnd + 1);
        assertGt(Time.timestamp(), _vestingEnd);
        _unlock();
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_getVotes_returns_zero_before_delegation() public view {
        assertEq(_xanV2Proxy.getVotes(_defaultSender), 0);
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

    /// @notice Claims (unlocks) all of `_defaultSender`'s currently vested tokens.
    function _unlock() internal {
        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();
    }

    /// @notice Begin vesting after the V2 upgrade completes; the voter-body delay is waited out during `setUp`.
    function _vestingSchedule() internal view override returns (uint48 start, uint48 duration) {
        start = Time.timestamp() + Parameters.DELAY_DURATION + 1 hours;
        duration = 24 hours;
    }
}
