// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Xan} from "../src/Xan.sol";

contract StorageTest is Test, Xan {
    function test_storageLocation() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(_XAN_STORAGE_LOCATION, expected);
    }
}
