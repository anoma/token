// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";

import {XanV1} from "../src/XanV1.sol";
import {MockDistribution} from "./mocks/Distribution.m.sol";

contract MerkleDistributorTest is Test, MockDistribution {
    MerkleDistributor internal _md;
    XanV1 internal _xanProxy;

    function setUp() public {
        _md = new MerkleDistributor({
            root: ROOT,
            startDate: Parameters.CLAIM_START_TIME,
            endDate: Parameters.CLAIM_START_TIME + Parameters.CLAIM_DURATION
        });

        _xanProxy = XanV1(_md.token());

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
                locked: _locked[i],
                proof: siblings,
                directionBits: directionBits
            });

            // Check if tokens were transferred locked or unlocked.
            assertEq(_xanProxy.balanceOf(voterAddr), VOTE_SHARE);
            if (_locked[i]) {
                assertEq(_xanProxy.unlockedBalanceOf(voterAddr), 0);
                assertEq(_xanProxy.lockedBalanceOf(voterAddr), VOTE_SHARE);
            } else {
                assertEq(_xanProxy.unlockedBalanceOf(voterAddr), VOTE_SHARE);
                assertEq(_xanProxy.lockedBalanceOf(voterAddr), 0);
            }
        }
    }
}
