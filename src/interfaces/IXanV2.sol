// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IXanV1} from "./IXanV1.sol";

interface IXanV2 is IXanV1 {
    /// @notice Mints tokens for an account.
    /// @param account The receiving account.
    /// @param value The value to be minted.
    /// @dev Can only be called by the `XanV2Forwarder` contract that has been created during initialization of v2.
    function mint(address account, uint256 value) external;

    /// @notice Returns the address of the forwarder contract being permitted to call the `mint` function.
    /// @return addr The forwarder address.
    function forwarder() external view returns (address addr);
}
