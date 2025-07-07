// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

/// @title IForeignReserveV1
/// @author Anoma Foundation, 2025
/// @notice The interface of the foreign reserve contract, an arbitrary executor owned by the Anoma (XAN) token and
/// receiving fees from the [Anoma token distributor](https://github.com/anoma/token-distributor) contract.
/// @custom:security-contact security@anoma.foundation
interface IForeignReserveV1 {
    /// @notice Emitted when the contract has received native tokens.
    /// @param sender The sender of the native token.
    /// @param value The native token value.
    event NativeTokenReceived(address sender, uint256 value);

    /// @notice Executes arbitrary calls.
    /// @param target The target address to call.
    /// @param value The value to send.
    /// @param data The data to send with the call.
    /// @return result The result of the call.
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory result);
}
