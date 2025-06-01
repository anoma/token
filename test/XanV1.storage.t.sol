// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {XanV1} from "../src/XanV1.sol";

contract XanV1StorageTest is Test, XanV1 {
    function test_storageLocation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(_XAN_V1_STORAGE_LOCATION, expected);
    }
}
