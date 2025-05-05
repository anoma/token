// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {ForwarderBase} from "@anoma/evm-protocol-adapter/ForwarderBase.sol";

import {XanV2} from "./XanV2.sol";

/// @notice A forwarder contract minting new XAN tokens for a recipient.
/// Note, that the forwarder contract is the recipient of newly minted XAN tokens.
contract XanV2Forwarder is ForwarderBase {
    XanV2 internal immutable _XAN_PROXY;

    error InvalidFunctionSelector(bytes4 expected, bytes4 actual);
    error InvalidMintRecipient(address recipient);

    constructor(address xanProxy, address protocolAdapter, bytes32 calldataCarrierLogicRef)
        ForwarderBase(protocolAdapter, calldataCarrierLogicRef)
    {
        _XAN_PROXY = XanV2(xanProxy);
    }

    /// @notice Forwards mint calls to the XAN proxy contract pointing to the `XanV2` implementation.

    /// @param input The `bytes` encoded mint calldata (including the `bytes4` function selector).
    /// @return output The empty output of the call.
    function _forwardCall(bytes calldata input) internal override returns (bytes memory output) {
        bytes4 selector = bytes4(input[:4]);

        bytes memory args = input[4:];

        // Check that that the mint function is the call target.
        if (selector != XanV2.mint.selector) {
            revert InvalidFunctionSelector({expected: XanV2.mint.selector, actual: selector});
        }
        // NOTE: The recipient address is not needed on the EVM side, because the forwarder receives the tokens.
        (address recipient, uint256 value) = abi.decode(args, (address, uint256));
        if (recipient == address(this)) {
            revert InvalidMintRecipient({recipient: address(this)});
        }

        output = bytes("");

        // Mint tokens for the forwarder contract.
        // NOTE: The calldata carrier resource must ensure that the recipient receives corresponding XAN resources.
        _XAN_PROXY.mint({account: address(this), value: value});
    }
}
