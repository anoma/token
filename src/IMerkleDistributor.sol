// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

interface IMerkleDistributor {
    /// @notice Emitted when tokens are claimed from the distributor.
    /// @param index The index in the balance tree that was claimed.
    /// @param to The address to which the tokens are sent.
    /// @param value The claimed value.
    event Claimed(uint256 indexed index, address indexed to, uint256 value);

    /// @notice The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token being distributed.
    /// @return addr The token address.
    function token() external returns (address addr);

    /// @notice The merkle root of the balance tree storing the claims.
    /// @return root The root of the Merkle tree.
    function merkleRoot() external returns (bytes32 root);

    /// @notice Claims tokens from the balance tree and sends it to an address.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The receiving address.
    /// @param value The value of tokens.
    /// @param value The locked value of tokens.
    /// @param proof The merkle proof to be verified.
    function claim(
        uint256 index,
        address to,
        uint256 value,
        uint256 lockedValue,
        bytes32[] calldata proof,
        uint256 directionBits
    )
        external;

    /// @notice Returns the value of unclaimed tokens.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The receiving address.
    /// @param value The value of tokens.
    /// @param value The locked value of tokens.
    /// @param proof The merkle proof to be verified.
    /// @return unclaimedValue The unclaimed value.
    function unclaimedBalance(
        uint256 index,
        address to,
        uint256 value,
        uint256 lockedValue,
        bytes32[] memory proof,
        uint256 directionBits
    )
        external
        returns (uint256 unclaimedValue);

    /// @notice Checks if an index on the merkle tree is claimed.
    /// @param index The index in the balance tree to be claimed.
    /// @return claimed True if the index is claimed.
    function isClaimed(uint256 index) external view returns (bool claimed);
}
