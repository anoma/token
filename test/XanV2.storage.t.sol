// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";

contract XanV2StorageTest is Test, XanV2 {
    function test_storage_slot() public pure {
        assertEq(_XAN_V2_STORAGE_LOCATION, SlotDerivation.erc7201Slot("anoma.storage.Xan.v2"));
    }
}
