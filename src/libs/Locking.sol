// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Locking {
    /// @notice A struct containing data associated with the token locking mechanism.
    /// @param lockedBalances The locked balances associated with the current implementation.
    /// @param lockedSupply The locked total supply associated with the current implementation.
    struct Data {
        mapping(address owner => uint256) lockedBalances;
        uint256 lockedSupply;
    }
}
