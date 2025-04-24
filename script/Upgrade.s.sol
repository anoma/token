// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.27;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV2} from "../test/mocks/XanV2.m.sol";

contract Deploy is Script {
    address internal constant _XAN_PROXY = address(0);

    function run() public {
        vm.startBroadcast();

        if (_XAN_PROXY == address(0)) revert("TODO");

        Upgrades.upgradeProxy({
            proxy: _XAN_PROXY,
            contractName: "XanV2.m.sol:XanV2",
            data: abi.encodeCall(XanV2.initializeV2, ())
        });

        vm.stopBroadcast();
    }
}
