// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/XanV2.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";

contract XanV2VestingStorageTest is Test, XanV2Vesting {
    // The values are irrelevant: this harness only reads the compile-time storage-location constant. The constructor
    // copies the schedule of the token, so a `XanV2` implementation stands in for it.
    constructor() XanV2Vesting(IERC20(address(new XanV2(address(1), 2, 3)))) {}

    function test_storage_slot() public pure {
        assertEq(_XAN_V2_VESTING_STORAGE_LOCATION, SlotDerivation.erc7201Slot("anoma.storage.XanV2Vesting"));
    }
}
