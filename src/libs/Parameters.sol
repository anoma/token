// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title Parameters
/// @author Anoma Foundation, 2025
/// @notice A library containing the token parameters.
/// @custom:security-contact security@anoma.foundation
library Parameters {
    /* ========== Xan V1 ========== */

    /// @notice The name of the token.
    string internal constant NAME = "Anoma";

    /// @notice The symbol of the token.
    string internal constant SYMBOL = "XAN";

    /// @notice The total supply amounting to 10 bn (10^10) tokens with 18 decimals.
    uint256 internal constant SUPPLY = 10 ** (10 + 18);

    /// @notice The minimal locked supply required for upgrades amounting to 25% of the total supply.
    uint256 internal constant MIN_LOCKED_SUPPLY = SUPPLY / 4;

    /// @notice The quorum ratio numerator.
    uint256 internal constant QUORUM_RATIO_NUMERATOR = 1;

    /// @notice The quorum ratio denominator.
    uint256 internal constant QUORUM_RATIO_DENOMINATOR = 2;

    /// @notice The delay duration that must pass to upgrade to a new implementation.
    uint32 internal constant DELAY_DURATION = 2 weeks;

    /* ========== Xan V2 ========== */

    /// @notice The timestamp at which the linear vesting of the formerly locked balances starts in `XanV2`.
    /// @dev Thu Oct 01 2026 12:00:00 UTC.
    uint48 internal constant VESTING_START = 1_790_856_000;

    /// @notice The duration over which formerly locked balances vest linearly in `XanV2`.
    /// @dev Three years. Vesting is continuous (every block).
    uint48 internal constant VESTING_DURATION = 3 * 365 days;

    /// @notice The initial owner who can upgrade the XAN proxy V2.
    //! IMPORTANT: This address is currently a placeholder and must be changed before scheduling the upgrade to V2.
    address internal constant INITIAL_OWNER = 0x0000000000000000000000000000000000000000;

    /* ========== Governance ========== */

    /// @notice The delay between a governor proposal's creation and the start of voting (timestamp clock).
    uint48 internal constant VOTING_DELAY = 1 days;

    /// @notice The duration of a governor proposal's voting window.
    uint32 internal constant VOTING_PERIOD = 1 weeks;

    /// @notice The minimum voting power required to create a governor proposal.
    uint256 internal constant PROPOSAL_THRESHOLD = 10 ** 18; // 1 XAN

    /// @notice Reaction-time margin added on top of a full voter cancel cycle when the `XanSecurityCouncil` module
    /// sizes its fast-track upgrade delay, so the voter body has time to notice and cancel.
    uint256 internal constant COUNCIL_CANCEL_BUFFER = 7 days;
}
