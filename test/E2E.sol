// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { MerkleDistributor } from "../src/MerkleDistributor.sol";
import { Xan } from "../src/Xan.sol";

import { MockDistribution } from "./Distribution.m.sol";

contract E2ETest is Test, MockDistribution {
    MerkleDistributor internal _md;
    Xan internal _xanProxy;

    function setUp() public {
        uint256 currentDate = block.timestamp;
        _md = new MerkleDistributor({ root: ROOT, startDate: currentDate, endDate: currentDate + 2 weeks });

        _xanProxy = Xan(_md.token());
    }

    function test_e2e() external {
        string[4] memory census = ["Alice", "Bob", "Carol", "Dave"];

        // Allocate token
        for (uint256 i = 0; i < census.length; ++i) {
            address voterAddr = voter(census[i]);

            assertEq(_xanProxy.balanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);

            (bytes32[] memory siblings, uint256 directionBits) = merkleProof({ index: voterId(census[i]) });

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
            assertEq(_xanProxy.unlockedBalanceOf(voterAddr), VOTE_SHARE);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);

            // TODO refactor: this should happen automatically
            // Call as voter.
            vm.prank(voterAddr);
            _xanProxy.lock(VOTE_SHARE);

            assertEq(_xanProxy.balanceOf(voterAddr), VOTE_SHARE);
            assertEq(_xanProxy.unlockedBalanceOf(voterAddr), 0);
            assertEq(_xanProxy.lockedBalanceOf(voterAddr), VOTE_SHARE);
        }

        // Deploy new implementation.
        address newImplementation = address(new Xan());
        assertNotEq(newImplementation, _xanProxy.implementation());

        // Vote for Implementation
        {
            vm.prank(voter("Alice"));
            _xanProxy.castVote(newImplementation);
            vm.expectRevert(abi.encodeWithSelector(Xan.QuorumNotReached.selector, newImplementation));
            _xanProxy.checkUpgradeCriteria(newImplementation);

            vm.prank(voter("Bob"));
            _xanProxy.castVote(newImplementation);

            vm.expectRevert(abi.encodeWithSelector(Xan.QuorumNotReached.selector, newImplementation));
            _xanProxy.checkUpgradeCriteria(newImplementation);

            vm.prank(voter("Carol"));
            _xanProxy.castVote(newImplementation);
        }
        // Delay period
        {
            // Delay period hasn't started.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotStarted.selector, newImplementation));
            _xanProxy.checkDelayPeriod(newImplementation);

            // Start the delay period
            _xanProxy.startDelayPeriod(newImplementation);

            // Delay period hasn't ended.
            vm.expectRevert(abi.encodeWithSelector(Xan.DelayPeriodNotEnded.selector, newImplementation));
            _xanProxy.checkDelayPeriod(newImplementation);

            // Advance to the end of the delay period
            skip(_xanProxy.DELAY_DURATION());

            // Check that the delay has passed
            _xanProxy.checkDelayPeriod(newImplementation);
        }

        // Upgrade
        {
            _xanProxy.upgradeToAndCall({ newImplementation: newImplementation, data: "" });

            // Check that the upgrade was successful.
            assertEq(_xanProxy.implementation(), newImplementation);
        }

        // Check that storage is as expected.
        {
            // The vote was reset.
            assertEq(_xanProxy.totalVotes(newImplementation), 0);

            // The most voted implementation is not set yet.
            assertEq(_xanProxy.mostVotedImplementation(), address(0));

            for (uint256 i = 0; i < census.length; ++i) {
                address voterAddr = voter(census[i]);

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
}

contract XanInternalTest is Test, Xan {
    function test_storageLocation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(_XAN_STORAGE_LOCATION, expected);
    }
}
