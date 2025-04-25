// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {MerkleTree} from "../MerkleTree.sol";

interface IMerkleDistributor {
    /// @notice Emitted when tokens are claimed from the distributor.
    /// @param index The index in the balance tree that was claimed.
    /// @param to The address to which the tokens are sent.
    /// @param value The claimed value.
    /// @param locked Whether the tokens are locked or not.
    event Claimed(uint256 indexed index, address indexed to, uint256 value, bool locked);

    /// @notice The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token being distributed.
    /// @return addr The token address.
    function token() external returns (address addr);

    /// @notice The merkle root of the balance tree storing the claims.
    /// @return root The root of the Merkle tree.
    function merkleRoot() external returns (bytes32 root);

    /// @notice Claims tokens from the balance tree and sends it to an address.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The receiving address.
    /// @param value The number of tokens to claim.
    /// @param locked Whether the tokens are locked or not.
    /// @param proof The merkle proof to be verified.
    function claim(uint256 index, address to, uint256 value, bool locked, MerkleTree.Proof calldata proof) external;

    /// @notice Burns unclaimed tokens.
    function burnUnclaimedTokens() external;

    /// @notice Returns the value of unclaimed tokens.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The receiving address.
    /// @param value The number of unclaimed tokens.
    /// @param locked Whether the tokens are locked or not.
    /// @param proof The merkle proof to be verified.
    function unclaimedBalance(uint256 index, address to, uint256 value, bool locked, MerkleTree.Proof calldata proof)
        external
        view
        returns (uint256 unclaimedValue);

    /// @notice Checks if an index on the merkle tree is claimed.
    /// @param index The index in the balance tree to be claimed.
    /// @return claimed True if the index is claimed.
    function isClaimed(uint256 index) external view returns (bool claimed);
}
