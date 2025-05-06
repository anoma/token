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
            root: _ROOT,
            startTime: Parameters.CLAIM_START_TIME,
            endTime: Parameters.CLAIM_START_TIME + Parameters.CLAIM_DURATION
        });

        _xanProxy = XanV1(_md.token());
    }

    function test_claim_reverts_if_the_start_time_is_in_the_future() public {
        (address addr, uint256 id) = personAddrAndId("Alice");

        vm.expectRevert(abi.encodeWithSelector(MerkleDistributor.StartTimeInTheFuture.selector), address(_md));

        vm.prank(addr);
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: _merkleProof({index: id})});
    }

    function test_claim_reverts_if_the_end_time_is_in_the_past() public {
        (address addr, uint256 id) = personAddrAndId("Alice");

        skip(Parameters.CLAIM_START_TIME + Parameters.CLAIM_DURATION);
        vm.expectRevert(abi.encodeWithSelector(MerkleDistributor.EndTimeInThePast.selector), address(_md));

        vm.prank(addr);
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: _merkleProof({index: id})});
    }

    function test_claim_reverts_if_already_claimed() public {
        skip(Parameters.CLAIM_START_TIME);
        (address addr, uint256 id) = personAddrAndId("Alice");

        vm.startPrank(addr);
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: _merkleProof({index: id})});

        // Claim again
        vm.expectRevert(abi.encodeWithSelector(MerkleDistributor.TokenAlreadyClaimed.selector, id), address(_md));
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: _merkleProof({index: id})});
        vm.stopPrank();
    }

    function test_claim_reverts_if_the_index_is_wrong() public {
        skip(Parameters.CLAIM_START_TIME);

        (address addr, uint256 id) = personAddrAndId("Alice");
        uint256 wrongIndex = 2;

        vm.prank(addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                MerkleDistributor.TokenClaimInvalid.selector, wrongIndex, addr, _TOKEN_SHARE, _locked[id]
            ),
            address(_md)
        );
        _md.claim({
            index: wrongIndex,
            to: addr,
            value: _TOKEN_SHARE,
            locked: _locked[id],
            proof: _merkleProof({index: id})
        });
    }

    function test_claim_reverts_if_the_receiver_is_wrong() public {
        skip(Parameters.CLAIM_START_TIME);

        (address addr, uint256 id) = personAddrAndId("Alice");
        address wrongReceiver = person("Bob");

        vm.prank(addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                MerkleDistributor.TokenClaimInvalid.selector, id, wrongReceiver, _TOKEN_SHARE, _locked[id]
            ),
            address(_md)
        );
        _md.claim({
            index: id,
            to: wrongReceiver,
            value: _TOKEN_SHARE,
            locked: _locked[id],
            proof: _merkleProof({index: id})
        });
    }

    function test_claim_reverts_if_the_value_is_wrong() public {
        skip(Parameters.CLAIM_START_TIME);

        (address addr, uint256 id) = personAddrAndId("Alice");
        uint256 wrongValue = 123;

        vm.prank(addr);
        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributor.TokenClaimInvalid.selector, id, addr, wrongValue, _locked[id]),
            address(_md)
        );
        _md.claim({index: id, to: addr, value: wrongValue, locked: _locked[id], proof: _merkleProof({index: id})});
    }

    function test_claim_reverts_if_the_locked_flag_is_wrong() public {
        skip(Parameters.CLAIM_START_TIME);

        (address addr, uint256 id) = personAddrAndId("Alice");
        bool wrongLockedFlag = false;

        vm.prank(addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                MerkleDistributor.TokenClaimInvalid.selector, id, addr, _TOKEN_SHARE, wrongLockedFlag
            ),
            address(_md)
        );
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: wrongLockedFlag, proof: _merkleProof({index: id})});
    }

    function test_claim_reverts_if_the_proof_is_wrong() public {
        skip(Parameters.CLAIM_START_TIME);

        (address addr, uint256 id) = personAddrAndId("Alice");
        bytes32[] memory wrongProof = _merkleProof({index: personId("Bob")});

        vm.prank(addr);
        vm.expectRevert(
            abi.encodeWithSelector(MerkleDistributor.TokenClaimInvalid.selector, id, addr, _TOKEN_SHARE, _locked[id]),
            address(_md)
        );
        _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: wrongProof});
    }

    function test_claim_increases_balances() public {
        skip(Parameters.CLAIM_START_TIME);

        for (uint256 i = 0; i < _census.length; ++i) {
            address addr = person(_census[i]);
            assertEq(_xanProxy.balanceOf(addr), 0);
            assertEq(_xanProxy.lockedBalanceOf(addr), 0);
        }

        _claimFor(_census);

        for (uint256 i = 0; i < _census.length; ++i) {
            address addr = person(_census[i]);
            // Check if tokens were transferred locked or unlocked.
            assertEq(_xanProxy.balanceOf(addr), _TOKEN_SHARE);
            if (_locked[i]) {
                assertEq(_xanProxy.unlockedBalanceOf(addr), 0);
                assertEq(_xanProxy.lockedBalanceOf(addr), _TOKEN_SHARE);
            } else {
                assertEq(_xanProxy.unlockedBalanceOf(addr), _TOKEN_SHARE);
                assertEq(_xanProxy.lockedBalanceOf(addr), 0);
            }
        }
    }

    function test_claim_sets_the_id_to_claimed() public {
        skip(Parameters.CLAIM_START_TIME);

        for (uint256 i = 0; i < _census.length; ++i) {
            assertFalse(_md.isClaimed(i));
        }

        _claimFor(_census);

        for (uint256 i = 0; i < _census.length; ++i) {
            assertTrue(_md.isClaimed(i));
        }
    }

    function _claimFor(string[] memory names) internal {
        for (uint256 i = 0; i < names.length; ++i) {
            (address addr, uint256 id) = personAddrAndId(names[i]);

            vm.prank(addr);
            _md.claim({index: id, to: addr, value: _TOKEN_SHARE, locked: _locked[id], proof: _merkleProof({index: id})});
        }
    }
}
