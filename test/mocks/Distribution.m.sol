// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import {MerkleTree} from "@openzeppelin/contracts/utils/structs/MerkleTree.sol";

import {Leaf} from "../../src/libs/Leaf.sol";
import {MockPersons} from "./Persons.m.sol";

contract MockDistribution is MockPersons {
    using MerkleTree for MerkleTree.Bytes32PushTree;

    uint8 internal constant _TREE_DEPTH = 2;

    uint256 internal constant _TOKEN_SHARE = 1_000_000_000 / (2 ** _TREE_DEPTH);

    bytes32 internal immutable _ROOT;

    /// @notice The hash representing the empty leaf that is not expected to be part of the tree.
    /// @dev Obtained from `sha256("EMPTY_LEAF")`.
    bytes32 internal constant _EMPTY_LEAF_HASH = 0x283d1bb3a401a7e0302d0ffb9102c8fc1f4730c2715a2bfd46a9d9209d5965e0;

    MerkleTree.Bytes32PushTree internal _tree;
    string[] internal _census;
    bool[] internal _locked;

    bytes32[4] internal _leafs;
    bytes32[2] internal _nodes;
    bytes32[2][4] internal _siblings;

    constructor() {
        _tree.setup({treeDepth: _TREE_DEPTH, zero: _EMPTY_LEAF_HASH});

        _census = new string[](4);
        _census[0] = "Alice";
        _census[1] = "Bob";
        _census[2] = "Carol";
        _census[3] = "Dave";

        _locked = new bool[](4);
        _locked[0] = true;
        _locked[1] = true;
        _locked[2] = false;
        _locked[3] = false;

        bytes32 newRoot;
        for (uint256 i = 0; i < 2 ** _TREE_DEPTH; ++i) {
            bytes32 leaf = Leaf.hash({index: i, to: person(i), value: _TOKEN_SHARE, locked: _locked[i]});

            _leafs[i] = leaf;

            uint256 index;
            (index, newRoot) = _tree.push(leaf);
        }

        _nodes[0] = Hashes.commutativeKeccak256(_leafs[0], _leafs[1]);
        _nodes[1] = Hashes.commutativeKeccak256(_leafs[2], _leafs[3]);

        _siblings[0][0] = _leafs[1];
        _siblings[0][1] = _nodes[1];

        _siblings[1][0] = _leafs[0];
        _siblings[1][1] = _nodes[1];

        _siblings[2][0] = _leafs[3];
        _siblings[2][1] = _nodes[0];

        _siblings[3][0] = _leafs[2];
        _siblings[3][1] = _nodes[0];

        _ROOT = newRoot;
    }

    function _merkleProof(uint256 index) internal view returns (bytes32[] memory siblings) {
        siblings = new bytes32[](2);

        for (uint256 i = 0; i < _TREE_DEPTH; ++i) {
            siblings[i] = _siblings[index][i];
        }
    }
}
