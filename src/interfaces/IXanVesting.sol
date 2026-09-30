// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IXanVesting
/// @author Anoma Foundation, 2026
/// @notice The interface of the contract vesting the XAN principals that the genesis distribution did not contain.
/// @dev The contract emits the `VestingScheduled` and `Unlocked` events of `IXanV2`.
/// @custom:security-contact security@anoma.foundation
interface IXanVesting {
    /// @notice An account and the principal vesting for it.
    /// @param account The account that can unlock the principal.
    /// @param principal The amount of XAN vesting for the account.
    struct Recipient {
        address account;
        uint256 principal;
    }

    /// @notice Emitted when a principal is added for an account.
    /// @param account The account the principal vests for.
    /// @param principal The amount of XAN vesting for the account.
    event PrincipalAdded(address indexed account, uint256 principal);

    /// @notice Emitted when the owner withdraws XAN that no locked balance needs.
    /// @param receiver The account that received the XAN.
    /// @param value The amount of XAN transferred to the receiver.
    event Withdrawn(address indexed receiver, uint256 value);

    /// @notice Unlocks the tokens of the caller that have vested since the last unlock and transfers them to the
    /// caller.
    /// @return value The amount of tokens transferred to the caller.
    function unlock() external returns (uint256 value);

    /// @notice Adds principals for accounts that have none yet, neither here nor in the XAN token.
    /// @dev The XAN balance must cover the total locked balance after adding all recipients.
    /// @param recipients The accounts and the principals vesting for them.
    function addRecipients(Recipient[] calldata recipients) external;

    /// @notice Transfers XAN that this contract holds above the total locked balance to a receiver.
    /// @param receiver The account that receives the XAN.
    /// @param value The amount of XAN to transfer, at most the XAN balance minus `totalLockedBalance()`.
    function withdraw(address receiver, uint256 value) external;

    /// @notice Returns the amount of tokens that an account can unlock (vested but not yet unlocked).
    /// @param account The account to query.
    /// @return value The currently unlockable amount.
    function unlockableBalanceOf(address account) external view returns (uint256 value);

    /// @notice Returns the amount of the principal of an account that this contract has already transferred to it.
    /// @param account The account to query.
    /// @return unlockedBalance The unlocked balance.
    function unlockedBalanceOf(address account) external view returns (uint256 unlockedBalance);

    /// @notice Returns the amount of the principal of an account that this contract still holds for it.
    /// @param account The account to query.
    /// @return lockedBalance The locked balance.
    function lockedBalanceOf(address account) external view returns (uint256 lockedBalance);

    /// @notice Returns the vesting principal of an account, which is fixed once it is added.
    /// @param account The account to query.
    /// @return principal The vesting principal.
    function principalOf(address account) external view returns (uint256 principal);

    /// @notice Returns the sum of the principals of all accounts.
    /// @return total The total principal.
    function totalPrincipal() external view returns (uint256 total);

    /// @notice Returns the sum of the locked balances of all accounts, which is the XAN that this contract must hold.
    /// @return total The total locked balance.
    function totalLockedBalance() external view returns (uint256 total);

    /// @notice Returns the timestamp at which vesting starts.
    /// @return start The vesting start timestamp.
    function vestingStart() external view returns (uint48 start);

    /// @notice Returns the timestamp at which vesting ends and all principals are fully vested.
    /// @return end The vesting end timestamp.
    function vestingEnd() external view returns (uint48 end);

    /// @notice Returns all accounts that have a principal, with their principals, in the order of addition.
    /// @return recipients The accounts and the principals vesting for them.
    function getRecipients() external view returns (Recipient[] memory recipients);

    // solhint-disable func-name-mixedcase

    /// @notice Returns the XAN token that this contract holds and transfers on unlock.
    /// @return xanToken The XAN token proxy.
    function XAN_TOKEN() external view returns (IERC20 xanToken);

    // solhint-enable func-name-mixedcase
}
