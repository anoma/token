// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";

/// @notice A Merkle tree implementation populating a tree of variable depth from left to right
/// and providing on-chain Merkle proofs.
/// @dev This is a modified version of the OpenZeppelin `MerkleTree` and `MerkleProof` implementation.
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.2.0/contracts/utils/structs/MerkleTree.sol
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.2.0/contracts/utils/cryptography/MerkleProof.sol
library MerkleTree {
    struct Tree {
        uint256 _nextLeafIndex;
        mapping(uint256 level => mapping(uint256 index => bytes32 node)) _nodes;
        bytes32[] _zeros;
    }

    /// @notice A proof struct consisting of siblings and direction bits proving inclusion of a leaf in the tree.
    /// @param siblings The siblings of the leaf to proof inclusion for.
    /// @param directionBits The direction bits indicating whether the siblings are left of right.
    struct Proof {
        bytes32[] siblings;
        uint256 directionBits;
    }

    /// @notice The hash representing the empty leaf that is not expected to be part of the tree.
    /// @dev Obtained from `sha256("EMPTY_LEAF")`.
    bytes32 internal constant _EMPTY_LEAF_HASH = 0x283d1bb3a401a7e0302d0ffb9102c8fc1f4730c2715a2bfd46a9d9209d5965e0;

    error TreeCapacityExceeded();
    error NonExistentLeafIndex(uint256 index);

    /// @notice Sets up the tree with a capacity (i.e. number of leaves) of `2**treeDepth`
    /// and computes the initial root of the empty tree.
    /// @param self The tree data structure.
    /// @param treeDepth The tree depth [0, 255].
    /// @return initialRoot The initial root of the empty tree.
    function setup(Tree storage self, uint8 treeDepth) internal returns (bytes32 initialRoot) {
        Arrays.unsafeSetLength(self._zeros, treeDepth);

        bytes32 currentZero = _EMPTY_LEAF_HASH;

        for (uint256 i = 0; i < treeDepth; ++i) {
            Arrays.unsafeAccess(self._zeros, i).value = currentZero;
            currentZero = keccak256(abi.encode(currentZero, currentZero));
        }

        initialRoot = currentZero;

        self._nextLeafIndex = 0;
    }

    /// @notice Pushes a leaf to the tree.
    /// @param self The tree data structure.
    /// @param leaf The leaf to add.
    /// @return index The index of the leaf.
    /// @return newRoot The new root of the tree.
    function push(Tree storage self, bytes32 leaf) internal returns (uint256 index, bytes32 newRoot) {
        // Cache the tree depth read.
        uint256 treeDepth = depth(self);

        // Get the next leaf index and increment it after assignment.
        // solhint-disable-next-line gas-increment-by-one
        index = self._nextLeafIndex++;

        // Check if the tree is already full.
        if (index + 1 > 1 << treeDepth) revert TreeCapacityExceeded();

        // Rebuild the branch from leaf to root.
        uint256 currentIndex = index;
        bytes32 currentLevelHash = leaf;
        for (uint256 i = 0; i < treeDepth; ++i) {
            // Store the current node hash at depth `i`.
            self._nodes[i][currentIndex] = currentLevelHash;

            // Compute the next level hash for depth `i+1`.
            // Check whether the `currentIndex` node is the left or right child of its parent.
            if (isLeftChild(currentIndex)) {
                // Compute the `currentLevelHash` using the right sibling.
                // Because we fill the tree from left to right,
                // the right child is empty and we must use the depth `i` zero hash.
                currentLevelHash = keccak256(abi.encode(currentLevelHash, Arrays.unsafeAccess(self._zeros, i).value));
            } else {
                // Compute the `currentLevelHash` using the left sibling.
                // Because we fill the tree from left to right,
                // the left child is the previous node at depth `i`.
                currentLevelHash = keccak256(abi.encode(self._nodes[i][currentIndex - 1], currentLevelHash));
            }

            currentIndex >>= 1;
        }
        newRoot = currentLevelHash;
    }

    /// @notice Computes a Merkle proof consisting of the sibling at each depth and the associated direction bit
    /// indicating whether the sibling is left (0) or right (1) at the respective depth.
    /// @param self The tree data structure.
    /// @param index The index of the leaf.
    /// @return proof The proof.
    function merkleProof(Tree storage self, uint256 index) internal view returns (Proof memory proof) {
        uint256 treeDepth = depth(self);

        // Check whether the index exists or not.
        if (index + 1 > self._nextLeafIndex) revert NonExistentLeafIndex(index);

        proof.siblings = new bytes32[](treeDepth);
        uint256 currentIndex = index;
        bytes32 currentSibling;

        // Iterate over the different tree levels starting at the bottom at the leaf level.
        for (uint256 i = 0; i < treeDepth; ++i) {
            // Check if the current node the left or right child of its parent.
            if (isLeftChild(currentIndex)) {
                // Sibling is right.
                currentSibling = self._nodes[i][currentIndex + 1];

                // Set the direction bit at position `i` to 1.
                proof.directionBits |= (1 << i);
            } else {
                // Sibling is left.
                currentSibling = self._nodes[i][currentIndex - 1];

                // Leave the direction bit at position `i` as 0.
            }

            // Check if the sibling is an empty subtree.
            if (currentSibling == bytes32(0)) {
                // The subtree node doesn't exist, so we store the zero hash instead.
                proof.siblings[i] = Arrays.unsafeAccess(self._zeros, i).value;
            } else {
                // The subtree node exists, so we store it.
                proof.siblings[i] = currentSibling;
            }

            // Shift the number one bit to the right to drop the last binary digit.
            currentIndex >>= 1;
        }
    }

    /// @notice Returns the tree depth.
    /// @param self The tree data structure.
    /// @return treeDepth The depth of the tree.
    function depth(Tree storage self) internal view returns (uint256 treeDepth) {
        treeDepth = self._zeros.length;
    }

    /// @notice Returns the number of leafs that have been added to the tree.
    /// @param self The tree data structure.
    /// @return count The number of leaves in the tree.
    function leafCount(Tree storage self) internal view returns (uint256 count) {
        count = self._nextLeafIndex;
    }

    /// @notice Checks whether a node is the left or right child according to its index.
    /// @param index The index to check.
    /// @return isLeft Whether this node is the left or right child.
    function isLeftChild(uint256 index) internal pure returns (bool isLeft) {
        isLeft = index & 1 == 0;
    }

    /// @notice Processes a Merkle proof consisting of siblings and direction bits and returns the resulting root.
    /// @param proof The proof.
    /// @param leaf The leaf.
    /// @return root The resulting root obtained by processing the leaf, siblings, and direction bits.
    function processProof(Proof memory proof, bytes32 leaf) internal pure returns (bytes32 root) {
        bytes32 computedHash = leaf;

        uint256 treeDepth = proof.siblings.length;
        for (uint256 i = 0; i < treeDepth; ++i) {
            if (isLeftSibling(proof.directionBits, i)) {
                // Left sibling
                computedHash = keccak256(abi.encode(proof.siblings[i], computedHash));
            } else {
                // Right sibling
                computedHash = keccak256(abi.encode(computedHash, proof.siblings[i]));
            }
        }
        root = computedHash;
    }

    /// @notice Checks whether a direction bit encodes the left or right sibling.
    /// @param directionBits The direction bits.
    /// @param d The index of the bit to check.
    /// @return isLeft Whether the sibling is left or right.
    function isLeftSibling(uint256 directionBits, uint256 d) internal pure returns (bool isLeft) {
        isLeft = (directionBits >> d) & 1 == 0;
    }
}
