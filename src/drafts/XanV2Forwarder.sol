// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {XanV2} from "./XanV2.sol";

/// @title XanV2Forwarder
/// @author Anoma Foundation, 2025
/// @notice A draft of a XanV2 forwarder contract minting new XAN tokens for a recipient.
/// Note, that the forwarder contract is the recipient of newly minted XAN tokens.
/// @custom:security-contact security@anoma.foundation
contract XanV2Forwarder {
    XanV2 internal immutable _XAN_PROXY;
    address internal immutable _PROTOCOL_ADAPTER;
    bytes32 internal immutable _CALLDATA_CARRIER_RESOURCE_KIND;

    error AddressZero();
    error UnauthorizedCaller(address caller);
    error InvalidFunctionSelector(bytes4 expected, bytes4 actual);
    error InvalidMintRecipient(address recipient);

    /// @notice Constructs a forwarder.
    /// @param xanProxy The of the XAN proxy contract.
    /// @param protocolAdapter The address of the protocol adapter.
    /// @param calldataCarrierLogicRef The logic reference of the associated calldata carrier resource.
    constructor(address xanProxy, address protocolAdapter, bytes32 calldataCarrierLogicRef) {
        if (xanProxy == address(0) || protocolAdapter == address(0)) revert AddressZero();

        _XAN_PROXY = XanV2(xanProxy);
        _PROTOCOL_ADAPTER = protocolAdapter;
        _CALLDATA_CARRIER_RESOURCE_KIND =
            _kind({logicRef: calldataCarrierLogicRef, labelRef: sha256(abi.encode(address(this)))});
    }

    /// @notice Forwards mint calls to the XAN proxy contract pointing to the `XanV2` implementation.
    /// @param input The `bytes` encoded mint calldata (including the `bytes4` function selector).
    /// @return output The empty output of the call.
    function forwardCall(bytes calldata input /* solhint-disable-line comprehensive-interface*/ )
        external
        returns (bytes memory output)
    {
        if (msg.sender != _PROTOCOL_ADAPTER) {
            revert UnauthorizedCaller(msg.sender);
        }

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

    /// @notice Computes the resource kind.
    /// @param logicRef The resource logic reference.
    /// @param labelRef The resource label reference.
    /// @return k The computed kind.
    function _kind(bytes32 logicRef, bytes32 labelRef) internal pure returns (bytes32 k) {
        k = sha256(abi.encode(logicRef, labelRef));
    }
}
