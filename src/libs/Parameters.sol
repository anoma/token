// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

// TODO! Replace placeholder values.
library Parameters {
    /// @notice The total supply of the token.
    uint256 internal constant SUPPLY = 1_000_000_000;

    /// @notice The quorum ration numerator.
    uint256 internal constant QUORUM_RATIO_NUMERATOR = 1;

    /// @notice The quorum ration denominator.
    uint256 internal constant QUORUM_RATIO_DENOMINATOR = 2;

    /// @notice The delay duration that must pass for to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;

    /// @notice The claim start time (Sun Jun 01 2025 12:00:00 UTC).
    uint48 internal constant CLAIM_START_TIME = 1748779200;

    /// @notice The claim duration.
    uint32 internal constant CLAIM_DURATION = 365 days;
}
