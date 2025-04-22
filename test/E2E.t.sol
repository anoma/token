// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {MerkleDistributor} from "../src/MerkleDistributor.sol";
import {Xan} from "../src/Xan.sol";

import {MockDistribution} from "./Distribution.m.sol";

contract E2ETest is Test, MockDistribution {
    MerkleDistributor internal _md;
    Xan internal _xanProxy;

    string[4] internal _census;

    address internal _implA;
    address internal _implB;
    address internal _implC;

    function setUp() public {
        // solhint-disable-next-line not-rely-on-time
        uint256 currentDate = block.timestamp;
        _md = new MerkleDistributor({root: ROOT, startDate: currentDate, endDate: currentDate + 2 weeks});

        _xanProxy = Xan(_md.token());

        _census = ["Alice", "Bob", "Carol", "Dave"];

        _implA = address(new Xan());
        _implB = address(new Xan());
        _implC = address(new Xan());

        // Allocate token
        for (uint256 i = 0; i < _census.length; ++i) {
            address voterAddr = voter(_census[i]);

            assertEq(_xanProxy.balanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);

            (bytes32[] memory siblings, uint256 directionBits) = _merkleProof({index: voterId(_census[i])});

            // Call as voter.
            vm.prank(voterAddr);
            _md.claim({
                index: i,
                to: voterAddr,
                value: VOTE_SHARE,
                lockedValue: VOTE_SHARE,
                proof: siblings,
                directionBits: directionBits
            });

            assertEq(_xanProxy.balanceOf(voterAddr), VOTE_SHARE);
            assertEq(_xanProxy.unlockedBalanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), VOTE_SHARE);
        }
    }

    function test_e2e_proposal_execution() public {
        // Vote for Implementation
        {
            vm.prank(voter("Alice"));
            _xanProxy.castVote(_implA);
            vm.expectRevert(abi.encodeWithSelector(Xan.QuorumNotReached.selector, _implA));
            _xanProxy.checkUpgradeCriteria(_implA);

            vm.prank(voter("Bob"));
            _xanProxy.castVote(_implA);

            vm.expectRevert(abi.encodeWithSelector(Xan.QuorumNotReached.selector, _implA));
            _xanProxy.checkUpgradeCriteria(_implA);

            vm.prank(voter("Carol"));
            _xanProxy.castVote(_implA);
        }

        // Delay period
        {
            // Delay period hasn't started.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotStarted.selector, _implA));
            _xanProxy.checkDelayPeriod(_implA);

            // Start the delay period
            _xanProxy.startDelayPeriod(_implA);

            // Delay period hasn't ended.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotEnded.selector, _implA));
            _xanProxy.checkDelayPeriod(_implA);

            // Advance to the end of the delay period
            skip(_xanProxy.delayDuration());

            // Check that the delay has passed
            _xanProxy.checkDelayPeriod(_implA);
        }

        // Upgrade
        {
            _xanProxy.upgradeToAndCall({newImplementation: _implA, data: ""});

            // Check that the upgrade was successful.
            assertEq(_xanProxy.implementation(), _implA);
        }

        // Check that storage is as expected.
        {
            // The vote was reset.
            assertEq(_xanProxy.totalVotes(_implA), 0);

            // The most voted implementation is not set yet.
            // TODO assertEq(_xanProxy.mostVotedImplementation(), address(0));

            for (uint256 i = 0; i < _census.length; ++i) {
                address voterAddr = voter(_census[i]);

                // Balances should be the same
                assertEq(_xanProxy.balanceOf(voterAddr), VOTE_SHARE);

                // Tokens should be unlocked
                assertEq(_xanProxy.unlockedBalanceOf(voterAddr), VOTE_SHARE);
                assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);

                // Call as voter to lock tokens
                vm.prank(voterAddr);
                _xanProxy.lock(VOTE_SHARE);

                assertEq(_xanProxy.balanceOf(voterAddr), VOTE_SHARE);
                assertEq(_xanProxy.unlockedBalanceOf(voterAddr), 0);
                assertEq(_xanProxy.lockedBalanceOf(voterAddr), VOTE_SHARE);
            }
        }
    }

    function test_castVote_ranks_proposals() public {
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

    function test_revokeVote_ranks_proposals() public {
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
}

contract XanInternalTest is Test, Xan {
    function test_storageLocation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(_XAN_STORAGE_LOCATION, expected);
    }
}
