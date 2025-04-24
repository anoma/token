// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Leaf} from "../../src/libs/Leaf.sol";
import {MerkleTree} from "../../src/MerkleTree.sol";
import {MockVoters} from "./Voters.m.sol";

contract MockDistribution is MockVoters {
    using MerkleTree for MerkleTree.Tree;

    uint8 internal constant _TREE_DEPTH = 2;

    uint256 public constant VOTE_SHARE = 1_000_000_000 / (2 ** _TREE_DEPTH);

    bytes32 public immutable ROOT;

    MerkleTree.Tree internal _tree;
    string[4] internal _census;
    bool[4] internal _locked;

    constructor() {
        _tree.setup({treeDepth: _TREE_DEPTH});

        _census = ["Alice", "Bob", "Carol", "Dave"];
        _locked = [true, true, false, false];

        bytes32 newRoot;
        for (uint256 i = 0; i < 2 ** _TREE_DEPTH; ++i) {
            bytes32 leaf = Leaf.hash({index: i, to: voter(i), value: VOTE_SHARE, locked: _locked[i]});

            uint256 index;
            (index, newRoot) = _tree.push(leaf);
        }

        ROOT = newRoot;
    }

    function _merkleProof(uint256 index) internal view returns (MerkleTree.Proof memory proof) {
        proof = _tree.merkleProof(index);
    }
}
