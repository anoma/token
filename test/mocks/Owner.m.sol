// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {ForeignReserveV1} from "../../src/ForeignReserveV1.sol";

contract MockOwner {
    ForeignReserveV1 internal _reserve;

    constructor(ForeignReserveV1 reserve) {
        _reserve = reserve;
    }

    function executeOnForeignReserve(address target, uint256 value, bytes calldata data) external {
        _reserve.execute({target: target, value: value, data: data});
    }
}
