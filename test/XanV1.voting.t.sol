// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV1} from "../src/XanV1.sol";

import {MockPersons} from "./mocks/Persons.m.sol";

contract XanV1VotingTest is Test, MockPersons {
    XanV1 internal _xanProxy;

    string[4] internal _census;

    address internal _governanceCouncil;
    address internal _implA;
    address internal _implB;
    address internal _implC;

    function setUp() public {
        (, address _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _governanceCouncil))
            })
        );

        _census = ["Alice", "Bob", "Carol", "Dave"];

        uint256 share = _xanProxy.totalSupply() / _census.length;

        _implA = address(new XanV1());
        _implB = address(new XanV1());
        _implC = address(new XanV1());

        // Allocate tokens
        for (uint256 i = 0; i < _census.length; ++i) {
            address voterAddr = _person(_census[i]);

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
        vm.prank(_person("Alice"));
        _xanProxy.castVote(_implA);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implA);

        vm.prank(_person("Bob"));
        _xanProxy.castVote(_implB);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implA);
        assertEq(_xanProxy.proposedImplementationByRank(1), _implB);

        vm.prank(_person("Carol"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implA);
        assertEq(_xanProxy.proposedImplementationByRank(1), _implB);
        assertEq(_xanProxy.proposedImplementationByRank(2), _implC);

        vm.prank(_person("Dave"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implC);
        assertEq(_xanProxy.proposedImplementationByRank(1), _implA);
        assertEq(_xanProxy.proposedImplementationByRank(2), _implB);
    }

    function test_revokeVote_ranks_implementations() public {
        vm.prank(_person("Alice"));
        _xanProxy.castVote(_implA);

        vm.prank(_person("Bob"));
        _xanProxy.castVote(_implB);

        vm.prank(_person("Carol"));
        _xanProxy.castVote(_implC);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implA);
        assertEq(_xanProxy.proposedImplementationByRank(1), _implB);
        assertEq(_xanProxy.proposedImplementationByRank(2), _implC);

        vm.prank(_person("Alice"));
        _xanProxy.revokeVote(_implA);

        assertEq(_xanProxy.proposedImplementationByRank(0), _implB);
        assertEq(_xanProxy.proposedImplementationByRank(1), _implC);
        assertEq(_xanProxy.proposedImplementationByRank(2), _implA);
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
        assertLe(_xanProxy.lockedSupply(), _xanProxy.totalSupply());
    }
}
