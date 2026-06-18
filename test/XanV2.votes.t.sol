// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {MockXanV2} from "./mocks/XanV2.m.sol";

contract XanV2VotesTest is Test {
    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;
    address internal _defaultSender;
    address internal _other;
    address internal _governanceCouncil;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();
        _other = address(uint160(1));
        _governanceCouncil = address(uint160(2));

        // Deploy proxy and mint tokens for the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _governanceCouncil))
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

    function test_getPastVotes_returns_the_checkpointed_value() public {
        // Use literal block numbers for the queried timepoint: with `via_ir` the optimizer rematerializes the
        // `NUMBER` opcode across the `vm.roll` cheatcode, so a `block.number`-derived local would read stale.
        vm.roll(100);
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);

        vm.roll(101);

        assertEq(_xanV2Proxy.getPastVotes(_defaultSender, 100), Parameters.SUPPLY);
    }

    function test_transfer_moves_voting_power_between_delegates() public {
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);
        vm.prank(_other);
        _xanV2Proxy.delegate(_other);

        // Unlock half the vested principal and transfer it to `_other`.
        vm.warp(Parameters.VESTING_START + Parameters.VESTING_DURATION / 2);
        vm.startPrank(_defaultSender);
        _xanV2Proxy.unlock();
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_other, Parameters.SUPPLY / 2);
        vm.stopPrank();

        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.getVotes(_other), Parameters.SUPPLY / 2);
    }

    function test_self_delegation_grants_voting_power_equal_to_balance() public {
        vm.prank(_defaultSender);
        _xanV2Proxy.delegate(_defaultSender);

        // Voting power tracks the full balance, including the still-locked (unvested) tokens.
        assertEq(_xanV2Proxy.getVotes(_defaultSender), _xanV2Proxy.balanceOf(_defaultSender));
        assertEq(_xanV2Proxy.getVotes(_defaultSender), Parameters.SUPPLY);
    }

    function test_no_voting_power_before_delegation() public view {
        assertEq(_xanV2Proxy.getVotes(_defaultSender), 0);
    }

    function test_clock_tracks_the_block_number() public view {
        assertEq(_xanV2Proxy.clock(), uint48(block.number));
        assertEq(_xanV2Proxy.CLOCK_MODE(), "mode=blocknumber&from=default");
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
