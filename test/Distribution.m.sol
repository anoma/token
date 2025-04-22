// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Leaf} from "../src/Leaf.sol";
import {MerkleTree} from "../src/MerkleTree.sol";
import {MockVoters} from "./Voters.m.sol";

contract MockDistribution is MockVoters {
    using MerkleTree for MerkleTree.Tree;

    MerkleTree.Tree internal _tree;

    uint8 internal constant _TREE_DEPTH = 2;

    uint256 public constant VOTE_SHARE = 1_000_000_000 / (2 * _TREE_DEPTH);

    bytes32 public immutable ROOT;

    constructor() {
        _tree.setup({treeDepth: _TREE_DEPTH});

        bytes32 newRoot;
        for (uint256 i = 0; i < 2 * _TREE_DEPTH; ++i) {
            bytes32 leaf = Leaf.hash({index: i, to: voter(i), value: VOTE_SHARE, lockedValue: VOTE_SHARE});

            uint256 index;
            (index, newRoot) = _tree.push(leaf);
        }

        ROOT = newRoot;
    }

    function _merkleProof(uint256 index) internal view returns (bytes32[] memory siblings, uint256 directionBits) {
        (siblings, directionBits) = _tree.merkleProof(index);
    }
}
