// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {MerkleDistributor} from "../src/MerkleDistributor.sol";
import {XanV1} from "../src/XanV1.sol";

import {MockDistribution} from "./Distribution.m.sol";

contract E2ETest is Test, MockDistribution {
    MerkleDistributor internal _md;
    XanV1 internal _xanProxy;

    string[4] internal _census;

    function setUp() public {
        // solhint-disable-next-line not-rely-on-time
        uint256 currentDate = block.timestamp;
        _md = new MerkleDistributor({root: ROOT, startDate: currentDate, endDate: currentDate + 2 weeks});

        _xanProxy = XanV1(_md.token());

        _census = ["Alice", "Bob", "Carol", "Dave"];

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
}
