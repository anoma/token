// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

interface IForeignReserve {
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory result);
}
