// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Script} from "forge-std/Script.sol";

import {IXanVesting} from "../src/interfaces/IXanVesting.sol";

/// @notice Computes the XAN that the council multisig sends to `XanVesting` now so that every present and future unlock
/// succeeds. It sends nothing.
contract ComputeXanVestingTopUpFull is Script {
    /// @notice Returns the XAN to send now so that every present and future unlock succeeds, or zero if the balance of
    /// `vesting` is already enough.
    /// @param vesting The `XanVesting` contract.
    /// @return topUp The XAN to send, in the smallest unit.
    function run(IXanVesting vesting) public view returns (uint256 topUp) {
        topUp = Math.saturatingSub(vesting.totalLockedBalance(), vesting.XAN_TOKEN().balanceOf(address(vesting)));
    }
}
