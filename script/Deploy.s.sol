// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";

contract Deploy is Script {
    bytes32 internal constant _ROOT = keccak256("TODO");

    function run() public {
        vm.startBroadcast();

        if (_ROOT == keccak256("TODO")) revert("TODO");

        uint48 startTime = Parameters.CLAIM_START_TIME;

        new MerkleDistributor({root: _ROOT, startTime: startTime, endTime: startTime + Parameters.CLAIM_DURATION});

        vm.stopBroadcast();
    }
}
