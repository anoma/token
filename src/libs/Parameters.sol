// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Parameters {
    /// @notice The total supply of the token amounting to 1 bn (10^9).
    uint256 internal constant SUPPLY = 1_000_000_000;

    /// @notice The minimal locked supply required for upgrades amounting to 25% of the total supply.
    uint256 internal constant MIN_LOCKED_SUPPLY = 250_000_000;

    /// @notice The quorum ration numerator.
    uint256 internal constant QUORUM_RATIO_NUMERATOR = 1;

    /// @notice The quorum ration denominator.
    uint256 internal constant QUORUM_RATIO_DENOMINATOR = 2;

    /// @notice The delay duration that must pass for to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;
}
