// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

library Parameters {
    /// @notice The total supply of the token..
    uint256 internal constant SUPPLY = 1_000_000_000;

    /// @notice The quorum required to upgrade to a new implementation.
    uint256 internal constant QUORUM = SUPPLY / 2;

    /// @notice The delay duration until to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;

    /// @notice The claim duration.
    uint32 internal constant CLAIM_DURATION = 365 days;
}
