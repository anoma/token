// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";

contract Deploy is Script {
    bytes32 internal constant _ROOT = keccak256("TODO"); // TODO replace

    function run() public {
        vm.startBroadcast();

        // solhint-disable-next-line gas-custom-errors;
        if (_ROOT == keccak256("TODO")) revert("TODO");

        // solhint-disable-next-line not-rely-on-time
        uint256 startDate = Parameters.CLAIM_START_TIME;

        new MerkleDistributor({root: _ROOT, startDate: startDate, endDate: startDate + Parameters.CLAIM_DURATION});

        vm.stopBroadcast();
    }
}
