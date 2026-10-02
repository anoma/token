// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Script} from "forge-std/Script.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {XAN_V2_VESTING_PROXY} from "./DeployXanV2Vesting.s.sol";

/// @notice Computes the XAN that the council multisig sends to `XanV2Vesting` now so that every unlock until a
/// timestamp succeeds. It sends nothing.
contract ComputeXanV2VestingTopUpUntil is Script {
    using Math for uint256;

    /// @notice Thrown if the timestamp lies before the current block.
    error TimestampInThePast(uint48 timestamp, uint48 currentTimestamp);

    /// @notice Returns the XAN to send now to the `XanV2Vesting` proxy of Ethereum mainnet and Sepolia so that every
    /// unlock until `timestamp` succeeds, or zero if its balance is already enough.
    /// @param timestamp The time until which every unlock must succeed, usually the time of the next top-up.
    /// @return topUp The XAN to send, in the smallest unit.
    function run(uint48 timestamp) public returns (uint256 topUp) {
        topUp = run({vesting: IXanV2Vesting(XAN_V2_VESTING_PROXY), timestamp: timestamp});
    }

    /// @notice Returns the XAN to send now so that every unlock until `timestamp` succeeds, or zero if the balance of
    /// `vesting` is already enough.
    /// @dev Reads `totalUnlockableBalance()` at `timestamp` and then restores the block timestamp.
    /// @param vesting The `XanV2Vesting` contract.
    /// @param timestamp The time until which every unlock must succeed, usually the time of the next top-up.
    /// @return topUp The XAN to send, in the smallest unit.
    function run(IXanV2Vesting vesting, uint48 timestamp) public returns (uint256 topUp) {
        uint48 currentTimestamp = Time.timestamp();
        require(
            currentTimestamp <= timestamp,
            TimestampInThePast({timestamp: timestamp, currentTimestamp: currentTimestamp})
        );

        uint256 balance = vesting.XAN_TOKEN().balanceOf(address(vesting));

        vm.warp(timestamp);
        uint256 unlockableAtTimestamp = vesting.totalUnlockableBalance();
        vm.warp(currentTimestamp);

        topUp = unlockableAtTimestamp.saturatingSub(balance);
    }
}
