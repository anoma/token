// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { MerkleDistributor } from "../src/MerkleDistributor.sol";

contract Deploy is Script {
    // function setUp() public {}

    function run() public {
        vm.startBroadcast();

        bytes32 root = 0;

        // solhint-disable-next-line not-rely-on-time
        uint256 startDate = block.timestamp + 5 minutes;

        new MerkleDistributor({ root: root, startDate: startDate, endDate: startDate + 4 weeks });

        vm.stopBroadcast();
    }
}
