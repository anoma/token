// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Script} from "forge-std/Script.sol";

import {IXanVesting} from "../src/interfaces/IXanVesting.sol";

/// @notice Computes the XAN that the Anoma Foundation wallet sends to `XanVesting` now so that every unlock until a
/// timestamp succeeds. It sends nothing.
contract ComputeXanVestingTopUpUntil is Script {
    /// @notice Thrown if the timestamp lies before the current block.
    error TimestampInThePast(uint48 timestamp, uint48 currentTimestamp);

    /// @notice Returns the XAN to send now so that every unlock until `timestamp` succeeds, or zero if the balance of
    /// `vesting` is already enough.
    /// @dev Reads `totalUnlockableBalance()` at `timestamp` and then restores the block timestamp.
    /// @param vesting The `XanVesting` contract.
    /// @param timestamp The time until which every unlock must succeed, usually the time of the next top-up.
    /// @return topUp The XAN to send, in the smallest unit.
    function run(IXanVesting vesting, uint48 timestamp) public returns (uint256 topUp) {
        uint48 currentTimestamp = Time.timestamp();
        require(
            currentTimestamp < timestamp + 1,
            TimestampInThePast({timestamp: timestamp, currentTimestamp: currentTimestamp})
        );

        uint256 balance = vesting.XAN_TOKEN().balanceOf(address(vesting));

        vm.warp(timestamp);
        uint256 unlockableAtTimestamp = vesting.totalUnlockableBalance();
        vm.warp(currentTimestamp);

        topUp = Math.saturatingSub(unlockableAtTimestamp, balance);
    }
}
