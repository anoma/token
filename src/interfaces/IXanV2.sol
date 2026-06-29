// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IXanV2
/// @author Anoma Foundation, 2026
/// @notice The interface of the Anoma (XAN) token contract version 2.
/// @custom:security-contact security@anoma.foundation
interface IXanV2 {
    /// @notice Emitted when the vesting schedule for the formerly locked balances is set, at upgrade time.
    /// @param start The timestamp at which vesting starts (may be in the future).
    /// @param duration The duration over which the locked balances vest linearly.
    event VestingScheduled(uint48 start, uint48 duration);

    /// @notice Emitted when an account unlocks vested tokens.
    /// @param account The account that unlocked tokens.
    /// @param value The amount of tokens that became spendable.
    event Unlocked(address indexed account, uint256 value);

    /// @notice Unlocks the tokens of the caller that have vested since the last unlock, making them spendable.
    /// @return value The amount of tokens that became spendable.
    function unlock() external returns (uint256 value);

    /// @notice Returns the amount of tokens that an account can unlock (vested but not yet unlocked).
    /// @param account The account to query.
    /// @return value The currently unlockable amount.
    function unlockableBalanceOf(address account) external view returns (uint256 value);

    /// @notice Returns the unlocked (spendable) token balance of an account.
    /// @param account The account to query.
    /// @return unlockedBalance The unlocked balance.
    function unlockedBalanceOf(address account) external view returns (uint256 unlockedBalance);

    /// @notice Returns the still-locked token balance of an account that has not vested or not been unlocked yet.
    /// @param account The account to query.
    /// @return lockedBalance The locked balance.
    function lockedBalanceOf(address account) external view returns (uint256 lockedBalance);

    /// @notice Returns the timestamp at which vesting started.
    /// @return start The vesting start timestamp.
    function vestingStart() external view returns (uint48 start);

    /// @notice Returns the timestamp at which vesting ends and all locked balances are fully vested.
    /// @return end The vesting end timestamp.
    function vestingEnd() external view returns (uint48 end);

    /// @notice Returns the implementation
    /// @return impl The implementation.
    function implementation() external view returns (address impl);
}
