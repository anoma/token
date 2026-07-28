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
    uint32 internal constant DELAY_DURATION = 14 days;

    /* ========== Xan V2 ========== */

    /// @notice The timestamp at which the linear vesting of the formerly locked balances starts in `XanV2`.
    /// @dev Sat Oct 31 2026 12:00:00 UTC.
    uint48 internal constant XAN_VESTING_START = 1_793_448_000;

    /// @notice The duration over which formerly locked balances vest linearly in `XanV2`.
    /// @dev Three years. Vesting is continuous (every block).
    uint48 internal constant XAN_VESTING_DURATION = 3 * 365 days;

    /* ========== Governance ========== */

    /// @notice The minimum voting power required to create a governor proposal.
    uint256 internal constant GOVERNOR_PROPOSAL_THRESHOLD = 25_000 * 10 ** 18; // 25k XAN

    /// @notice The delay between a governor proposal's creation and the start of voting (timestamp clock).
    uint48 internal constant GOVERNOR_VOTING_DELAY = 7 days;

    /// @notice The duration of a governor proposal's voting window.
    uint32 internal constant GOVERNOR_VOTING_PERIOD = 14 days;

    /// @notice The governor quorum numerator over `GovernorVotesQuorumFraction`'s denominator of 100 — the quorum as
    /// a percentage of the total voting supply.
    uint256 internal constant GOVERNOR_QUORUM_NUMERATOR = 10; // 10% of the checkpointed total supply.

    /// @notice The minimum delay of the governance `TimelockController`, applying to every timelock operation.
    uint256 internal constant TIMELOCK_MIN_DELAY = 14 days;

    /// @notice Margin the `XanUpgradeCouncilModule` adds on top of a full voter cancel cycle when sizing its
    /// upgrade delay, giving the voter body time to notice a scheduled upgrade and start cancelling it.
    uint256 internal constant COUNCIL_EXTRA_DELAY = 7 days;
}
