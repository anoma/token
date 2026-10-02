// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Script} from "forge-std/Script.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {XAN_V2_VESTING_PROXY} from "./DeployXanV2Vesting.s.sol";

/// @notice Computes the XAN that the council multisig sends to `XanV2Vesting` now so that every present and future
/// unlock succeeds. It sends nothing.
contract ComputeXanV2VestingTopUpFull is Script {
    using Math for uint256;

    /// @notice Returns the XAN to send now to the `XanV2Vesting` proxy of Ethereum mainnet and Sepolia so that every
    /// present and future unlock succeeds, or zero if its balance is already enough.
    /// @return topUp The XAN to send, in the smallest unit.
    function run() public view returns (uint256 topUp) {
        topUp = run(IXanV2Vesting(XAN_V2_VESTING_PROXY));
    }

    /// @notice Returns the XAN to send now so that every present and future unlock succeeds, or zero if the balance of
    /// `vesting` is already enough.
    /// @param vesting The `XanV2Vesting` contract.
    /// @return topUp The XAN to send, in the smallest unit.
    function run(IXanV2Vesting vesting) public view returns (uint256 topUp) {
        topUp = vesting.totalLockedBalance().saturatingSub(vesting.XAN_TOKEN().balanceOf(address(vesting)));
    }
}
