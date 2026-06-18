// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.30;

import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";

contract ScheduleCouncilUpgradeToXanV2 is Script {
    error InvalidOwnerAddress();
    error InvalidVestingStart();
    error InvalidVestingDuration();

    function run(address proxy) public returns (address implV2) {
        Options memory opts;

        require(Parameters.INITIAL_OWNER != address(0), InvalidOwnerAddress());
        require(Parameters.VESTING_START != 0, InvalidVestingStart());
        require(Parameters.VESTING_DURATION != 0, InvalidVestingDuration());

        // Bind the owner and vesting schedule into the implementation bytecode at deployment (the trusted step). The
        // scheduled implementation address is fixed, so whoever later executes the (permissionless) upgrade cannot
        // change these via calldata. Always use the `Parameters` constants so the vesting schedule cannot be picked
        // wrong.
        opts.constructorData =
            abi.encode(Parameters.INITIAL_OWNER, Parameters.VESTING_START, Parameters.VESTING_DURATION);

        vm.startBroadcast();

        implV2 = Upgrades.prepareUpgrade({contractName: "XanV2.sol:XanV2", opts: opts});

        XanV1(proxy).scheduleCouncilUpgrade({impl: implV2});

        vm.stopBroadcast();
    }
}
