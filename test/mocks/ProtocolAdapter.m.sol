// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XanV2Forwarder} from "../../src/drafts/XanV2Forwarder.sol";

contract MockProtocolAdapter {
    /// @notice A data structure containing the input data to be forwarded to the untrusted forwarder contract
    /// and the anticipated output data.
    /// @param untrustedForwarder The forwarder contract forwarding the call.
    /// @param input The input data for the forwarded call that might or might not include the `bytes4` function selector.
    /// @param output The anticipated output data from the forwarded call.
    struct ForwarderCalldata {
        address untrustedForwarder;
        bytes input;
        bytes output;
    }

    event MockForwardCall(address indexed untrustedForwarder, bytes input, bytes output);

    function executeForwarderCall(ForwarderCalldata calldata call) external {
        bytes memory output = XanV2Forwarder(call.untrustedForwarder).forwardCall(call.input);

        emit MockForwardCall({untrustedForwarder: call.untrustedForwarder, input: call.input, output: output});
    }
}
