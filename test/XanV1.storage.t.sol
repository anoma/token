// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {XanV1} from "../src/XanV1.sol";

contract XanV1StorageTest is Test, XanV1 {
    function test_storage_slot() public pure {
        assertEq(_XAN_V1_STORAGE_LOCATION, SlotDerivation.erc7201Slot("anoma.storage.Xan.v1"));
    }
}
