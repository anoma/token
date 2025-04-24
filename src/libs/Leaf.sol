// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

library Leaf {
    function hash(uint256 index, address to, uint256 value, bool locked) internal pure returns (bytes32 leafHash) {
        leafHash = keccak256(abi.encode(index, to, value, locked));
    }
}
