// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Xan} from "../src/Xan.sol";

import {MockVoters} from "./Voters.m.sol";

contract XanTest is Test, MockVoters {
    Xan internal _xanProxy;

    string[4] internal _census;

    address internal _implA;
    address internal _implB;
    address internal _implC;

    function setUp() public {
        (, address _defaultSender,) = vm.readCallers();

        _xanProxy = Xan(
            Upgrades.deployUUPSProxy({
                contractName: "Xan.sol:Xan",
                initializerData: abi.encodeCall(Xan.initialize, (_defaultSender))
            })
        );

        _census = ["Alice", "Bob", "Carol", "Dave"];

        uint256 share = _xanProxy.totalSupply() / _census.length;

        _implA = address(new Xan());
        _implB = address(new Xan());
        _implC = address(new Xan());

        // Allocate tokens
        for (uint256 i = 0; i < _census.length; ++i) {
            address voterAddr = voter(_census[i]);

            assertEq(_xanProxy.balanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);

            vm.prank(_defaultSender);
            _xanProxy.transferAndLock({to: voterAddr, value: share});

            assertEq(_xanProxy.balanceOf(voterAddr), share);
            assertEq(_xanProxy.unlockedBalanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), share);
        }
    }

    function test_castVote_ranks_implementations() public {
        vm.prank(voter("Alice"));
        _xanProxy.castVote(_implA);

        assertEq(_xanProxy.implementationByRank(0), _implA);

        vm.prank(voter("Bob"));
        _xanProxy.castVote(_implB);

        assertEq(_xanProxy.implementationByRank(0), _implA);
        assertEq(_xanProxy.implementationByRank(1), _implB);

        vm.prank(voter("Carol"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.implementationByRank(0), _implA);
        assertEq(_xanProxy.implementationByRank(1), _implB);
        assertEq(_xanProxy.implementationByRank(2), _implC);

        vm.prank(voter("Dave"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.implementationByRank(0), _implC);
        assertEq(_xanProxy.implementationByRank(1), _implA);
        assertEq(_xanProxy.implementationByRank(2), _implB);
    }

    function test_revokeVote_ranks_implementations() public {
        vm.prank(voter("Alice"));
        _xanProxy.castVote(_implA);

        vm.prank(voter("Bob"));
        _xanProxy.castVote(_implB);

        vm.prank(voter("Carol"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.implementationByRank(0), _implA);
        assertEq(_xanProxy.implementationByRank(1), _implB);
        assertEq(_xanProxy.implementationByRank(2), _implC);

        vm.prank(voter("Alice"));
        _xanProxy.revokeVote(_implA);

        assertEq(_xanProxy.implementationByRank(0), _implB);
        assertEq(_xanProxy.implementationByRank(1), _implC);
        assertEq(_xanProxy.implementationByRank(2), _implA);
    }

    function testFuzz_lockedBalanceOf_and_unlockedBalanceOf_sum_to_balanceOf(address owner) public view {
        assertEq(_xanProxy.lockedBalanceOf(owner) + _xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_lockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.lockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_unlockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function invariant_lockedBalance() public view {
        assertLe(_xanProxy.lockedTotalSupply(), _xanProxy.totalSupply());
    }
}
