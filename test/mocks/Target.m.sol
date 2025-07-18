// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

contract MockTarget {
    event Called(address indexed from, uint256 indexed value, bytes data);

    error CallReverted();

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    fallback() external payable {
        emit Called(msg.sender, msg.value, msg.data);
    }

    function ping() external payable returns (string memory message) {
        emit Called(msg.sender, msg.value, msg.data);
        message = "pong";
    }

    function revertingCall() external pure {
        revert CallReverted();
    }
}
