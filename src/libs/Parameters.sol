// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

library Parameters {
    /// @notice The total supply of the token..
    uint256 internal constant SUPPLY = 1_000_000_000;

    /// @notice The quorum required to upgrade to a new implementation.
    uint256 internal constant QUORUM = SUPPLY / 2;

    /// @notice The delay duration until to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;

    /// @notice The claim start time (Sun Jun 01 2025 12:00:00 UTC).
    uint48 internal constant CLAIM_START_TIME = 1748779200; // TODO replace by real time

    /// @notice The claim duration.
    uint32 internal constant CLAIM_DURATION = 365 days; // TODO replace by real duration

    /// @notice The recipient of unclaimed tokens after the claim period.
    address internal constant UNCLAIMED_TOKEN_RECIPIENT = address(0);
}
