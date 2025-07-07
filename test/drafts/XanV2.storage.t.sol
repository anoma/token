// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {XanV2} from "../../src/drafts/XanV2.sol";

contract XanV2StorageTest is Test, XanV2 {
    function test_storageLocation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v2")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(_XAN_V2_STORAGE_LOCATION, expected);
    }
}
