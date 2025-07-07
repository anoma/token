// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Locking
/// @author TODO, 2025
/// @notice A library containing a data structure to store the locked balances and the locked supply.
/// @custom:security-contact TODO
library Locking {
    /// @notice A struct containing data associated with the token locking mechanism.
    /// @param lockedBalances The locked balances associated with the current implementation.
    /// @param lockedSupply The locked total supply associated with the current implementation.
    struct Data {
        mapping(address owner => uint256) lockedBalances;
        uint256 lockedSupply;
    }
}
