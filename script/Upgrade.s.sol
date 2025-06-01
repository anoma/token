// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {XanV2Forwarder} from "../src/drafts/XanV2Forwarder.sol";

contract Deploy is Script {
    address internal constant _XAN_PROXY = address(0);

    address internal constant _PROTOCOL_ADAPTER = address(0);
    bytes32 internal constant _CALLDATA_CARRIER_LOGIC_REF = bytes32(0);

    function run() public {
        vm.startBroadcast();

        if (_XAN_PROXY == address(0)) revert("TODO");

        if (_PROTOCOL_ADAPTER == address(0)) revert("TODO");

        if (_CALLDATA_CARRIER_LOGIC_REF == bytes32(0)) revert("TODO");

        address xanV2Forwarder = address(
            new XanV2Forwarder({
                xanProxy: address(this),
                protocolAdapter: _PROTOCOL_ADAPTER,
                calldataCarrierLogicRef: _CALLDATA_CARRIER_LOGIC_REF
            })
        );

        Upgrades.upgradeProxy({
            proxy: _XAN_PROXY,
            contractName: "XanV2.sol:XanV2",
            data: abi.encodeCall(XanV2.initializeV2, (xanV2Forwarder))
        });

        vm.stopBroadcast();
    }
}
