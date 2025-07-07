// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Parameters
/// @author Anoma Foundation, 2025
/// @notice A library containing the token parameters.
/// @custom:security-contact security@anoma.foundation
library Parameters {
    /// @notice The name of the token.
    string internal constant NAME = "Anoma";

    /// @notice The symbol of the token.
    string internal constant SYMBOL = "XAN";

    /// @notice The total supply amounting to 10 bn (10^10) tokens with 18 decimals.
    uint256 internal constant SUPPLY = 10 ** (10 + 18);

    /// @notice The minimal locked supply required for upgrades amounting to 25% of the total supply.
    uint256 internal constant MIN_LOCKED_SUPPLY = SUPPLY / 4;

    /// @notice The quorum ration numerator.
    uint256 internal constant QUORUM_RATIO_NUMERATOR = 1;

    /// @notice The quorum ration denominator.
    uint256 internal constant QUORUM_RATIO_DENOMINATOR = 2;

    /// @notice The delay duration that must pass for to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;
}
