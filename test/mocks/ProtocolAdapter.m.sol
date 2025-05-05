// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {IForwarder} from "@anoma/evm-protocol-adapter/ForwarderBase.sol";

import {ForwarderCalldata} from "@anoma/evm-protocol-adapter/Types.sol";

contract MockProtocolAdapter {
    event MockForwardCall(address indexed untrustedForwarder, bytes input, bytes output);

    function executeForwarderCall(ForwarderCalldata calldata call) external {
        bytes memory output = IForwarder(call.untrustedForwarder).forwardCall(call.input);

        emit MockForwardCall({untrustedForwarder: call.untrustedForwarder, input: call.input, output: output});
    }
}
