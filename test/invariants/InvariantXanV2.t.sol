// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {StdInvariant, Test} from "forge-std/Test.sol";

import {Parameters} from "../../src/libs/Parameters.sol";
import {XanV1} from "../../src/XanV1.sol";
import {XanV2} from "../../src/XanV2.sol";
import {MockXanV2} from "../mocks/MockXanV2.sol";
import {XanV2Handler} from "./HandlerXanV2.t.sol";

contract XanV2Invariants is StdInvariant, Test {
    address internal immutable _GOVERNANCE_COUNCIL = makeAddr("governanceCouncil");

    XanV1 public xanV1Proxy;
    XanV2 public token;
    XanV2Handler public handler;

    address internal _xanV2Impl;
    address internal _defaultSender;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        // Deploy the V1 proxy and mint the whole supply to the `_defaultSender`.
        xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _GOVERNANCE_COUNCIL))
            })
        );

        // Start vesting well after the upgrade completes (which waits out the voter-body delay), so the fuzzing
        // sequence begins before the vesting period and can warp forward through it.
        uint48 vestingStart = Time.timestamp() + 8 weeks;
        uint48 vestingDuration = 8 weeks;

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        _xanV2Impl = address(new MockXanV2(xanV1Proxy.implementation(), _defaultSender, vestingStart, vestingDuration));

        // Win the voter-body upgrade vote for `_xanV2Impl` and wait out the delay so the upgrade can be executed.
        vm.startPrank(_defaultSender);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_defaultSender));
        xanV1Proxy.castVote(_xanV2Impl);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();
        skip(Parameters.DELAY_DURATION);

        // Upgrade the proxy to V2.
        UnsafeUpgrades.upgradeProxy({
            proxy: address(xanV1Proxy), newImpl: _xanV2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        token = XanV2(address(xanV1Proxy));

        handler = new XanV2Handler(token, _defaultSender);

        // Register the handler for invariant fuzzing.
        targetContract(address(handler));
    }

    // A user can vote with their entire balance, and votes are conserved across arbitrary delegation.
    // Invariant: for every actor, voting power equals the sum of the full balances — locked, unlocked, vested, or
    // unvested alike — of all actors that have delegated to it. Guards the composition of the unlocked-only `_update`
    // transfer gate with `ERC20Votes`, which checkpoints the whole balance, and holds under self-, cross-, and
    // no-delegation. Self-delegation collapses this to `getVotes(actor) == balanceOf(actor)`.
    function invariant_votes_equal_delegated_balance() public view {
        address[] memory actors = handler.getActors();

        for (uint256 i = 0; i < actors.length; ++i) {
            address delegatee = actors[i];

            uint256 delegatedBalance;
            for (uint256 j = 0; j < actors.length; ++j) {
                if (token.delegates(actors[j]) == delegatee) {
                    delegatedBalance += token.balanceOf(actors[j]);
                }
            }

            assertEq(token.getVotes(delegatee), delegatedBalance, "votes != delegated balance");
        }
    }

    // Invariant: the total supply is fixed. `transfer` moves tokens between accounts and `unlock` only reclassifies
    // locked principal as spendable; neither mints nor burns, so the supply never leaves its V1-minted value.
    function invariant_total_supply_constant() public view {
        assertEq(token.totalSupply(), Parameters.SUPPLY, "total supply changed");
    }

    // Invariant: per actor, the unlockable (vested-but-not-yet-unlocked) balance never exceeds the still-locked
    // balance, and the locked balance never exceeds the token balance. The latter is what keeps `unlockedBalanceOf`
    // (`balanceOf - lockedBalanceOf`) from underflowing.
    function invariant_locked_balance_accounting() public view {
        address[] memory actors = handler.getActors();

        for (uint256 i = 0; i < actors.length; ++i) {
            address actor = actors[i];

            assertLe(token.unlockableBalanceOf(actor), token.lockedBalanceOf(actor), "unlockable > locked");
            assertLe(token.lockedBalanceOf(actor), token.balanceOf(actor), "locked > balance");
        }
    }
}
