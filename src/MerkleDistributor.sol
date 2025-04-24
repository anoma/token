// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

// Copied and modified from: https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {MerkleTree} from "../src/MerkleTree.sol";
import {IMerkleDistributor} from "./interfaces/IMerkleDistributor.sol";

import {Leaf} from "./libs/Leaf.sol";
import {XanV1} from "./XanV1.sol";

/// @title MerkleDistributor
/// @author Uniswap 2020, Modified by Anoma Foundation
/// @notice A component distributing claimable [ERC-20](https://eips.ethereum.org/EIPS/eip-20) tokens via a merkle tree.
contract MerkleDistributor is IMerkleDistributor {
    using SafeERC20 for XanV1;

    /// @notice The token to distribute.
    XanV1 internal immutable _XAN;

    /// @notice The root of the merkle tree containing the claimable balances.
    bytes32 internal immutable _ROOT;

    /// @notice The start data of the claim.
    uint256 internal immutable _START_DATE;

    /// @notice The end time of the claim.
    uint256 internal immutable _END_DATE;

    /// @notice A packed array of booleans containing the information who claimed.
    mapping(uint256 claimedWordIndex => uint256 claimedWord) internal _claimedBitMap;

    error StartTimeAfterEndTime();
    error StartTimeInTheFuture();
    error StartTimeInThePast();
    error EndTimeInThePast();

    /// @notice Thrown if tokens have been already claimed from the distributor.
    /// @param index The index in the balance tree that was already claimed.
    error TokenAlreadyClaimed(uint256 index);

    /// @notice Thrown if a claim is invalid.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The address to which the tokens should be sent.
    /// @param value The value to be claimed.
    /// @param locked Whether the tokens are locked or not.
    error TokenClaimInvalid(uint256 index, address to, uint256 value, bool locked);

    /// @notice Initializes the distributor.
    /// @param root The merkle root of the balance tree.
    /// @param startTime The start time of the claim period.
    /// @param endTime The end time of the claim period.
    constructor(bytes32 root, uint256 startTime, uint256 endTime) {
        // Validate dates
        // solhint-disable gas-strict-inequalities
        {
            if (startTime >= endTime) revert StartTimeAfterEndTime();

            uint64 currentTime = Time.timestamp();

            if (startTime < currentTime) revert StartTimeInThePast();
            _START_DATE = startTime;

            if (endTime <= currentTime) revert EndTimeInThePast();
            _END_DATE = endTime;
        }
        // solhint-enable  gas-strict-inequalities

        _XAN = XanV1(
            address(
                new ERC1967Proxy({
                    implementation: address(new XanV1()),
                    _data: abi.encodeCall(XanV1.initialize, (address(this)))
                })
            )
        );

        _ROOT = root;
    }

    /// @inheritdoc IMerkleDistributor
    function claim(uint256 index, address to, uint256 value, bool locked, MerkleTree.Proof calldata proof)
        external
        override
    {
        // solhint-disable not-rely-on-time
        // slither-disable-next-line timestamp
        if (block.timestamp < _START_DATE) revert StartTimeInTheFuture();

        // slither-disable-next-line timestamp
        if (_END_DATE < block.timestamp) revert EndTimeInThePast();
        // solhint-enable not-rely-on-time

        if (isClaimed(index)) revert TokenAlreadyClaimed(index);
        if (!_verifyProof({index: index, to: to, value: value, locked: locked, proof: proof})) {
            revert TokenClaimInvalid({index: index, to: to, value: value, locked: locked});
        }

        _setClaimed(index);
        emit Claimed({index: index, to: to, value: value, locked: locked});

        if (locked) {
            _XAN.transferAndLock({to: to, value: value});
        } else {
            _XAN.safeTransfer({to: to, value: value});
        }
    }

    /// @inheritdoc IMerkleDistributor
    function token() external view override returns (address addr) {
        addr = address(_XAN);
    }

    /// @inheritdoc IMerkleDistributor
    function merkleRoot() external view override returns (bytes32 root) {
        root = _ROOT;
    }

    /// @inheritdoc IMerkleDistributor
    function unclaimedBalance(uint256 index, address to, uint256 value, bool locked, MerkleTree.Proof calldata proof)
        public
        view
        override
        returns (uint256 unclaimedValue)
    {
        if (isClaimed(index)) return 0;

        return unclaimedValue =
            _verifyProof({index: index, to: to, value: value, locked: locked, proof: proof}) ? value : 0;
    }

    /// @inheritdoc IMerkleDistributor
    function isClaimed(uint256 index) public view override returns (bool claimed) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = _claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        claimed = claimedWord & mask == mask;
    }

    /// @notice Sets an index in the merkle tree to be claimed.
    /// @param index The index in the balance tree to be claimed.
    function _setClaimed(uint256 index) internal {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        _claimedBitMap[claimedWordIndex] = _claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    /// @notice Verifies a Merkle inclusion proof.
    /// @param index The index in the balance tree to be claimed.
    /// @param to The receiving address.
    /// @param value The value of tokens.
    /// @param locked Whether the tokens are locked or not.
    /// @param proof The merkle proof to be verified.
    /// @return valid Whether the proof is valid or not.
    function _verifyProof(uint256 index, address to, uint256 value, bool locked, MerkleTree.Proof calldata proof)
        internal
        view
        returns (bool valid)
    {
        bytes32 leaf = Leaf.hash({index: index, to: to, value: value, locked: locked});

        bytes32 computedRoot = MerkleTree.processProof({proof: proof, leaf: leaf});

        valid = computedRoot == _ROOT;
    }
}
