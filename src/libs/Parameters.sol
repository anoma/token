// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

library Parameters {
    /// @notice The total supply amounting to 1 bn (10^9) tokens with 18 decimals.
    uint256 internal constant SUPPLY = 10 ** (9 + 18);

    /// @notice The minimal locked supply required for upgrades amounting to 25% of the total supply.
    uint256 internal constant MIN_LOCKED_SUPPLY = SUPPLY / 4;

    /// @notice The quorum ration numerator.
    uint256 internal constant QUORUM_RATIO_NUMERATOR = 1;

    /// @notice The quorum ration denominator.
    uint256 internal constant QUORUM_RATIO_DENOMINATOR = 2;

    /// @notice The delay duration that must pass for to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;
}
