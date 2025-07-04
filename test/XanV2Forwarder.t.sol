// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {ForwarderBase} from "@anoma/evm-protocol-adapter/forwarders/ForwarderBase.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {XanV2Forwarder} from "../src/drafts/XanV2Forwarder.sol";
import {MockProtocolAdapter} from "../test/mocks/ProtocolAdapter.m.sol";

contract XanV2ForwarderUnitTest is Test {
    address internal _defaultSender;
    address internal _governanceCouncil;
    XanV2 internal _xanV2Proxy;
    XanV2Forwarder internal _xanV2Forwarder;
    MockProtocolAdapter internal _mockProtocolAdapter = new MockProtocolAdapter();

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanV2Proxy = XanV2(Upgrades.deployUUPSProxy({contractName: "XanV2.sol:XanV2", initializerData: ""}));

        _xanV2Forwarder = new XanV2Forwarder({
            xanProxy: address(_xanV2Proxy),
            protocolAdapter: address(_mockProtocolAdapter),
            calldataCarrierLogicRef: bytes32(0)
        });

        _xanV2Proxy.initializeV2({
            initialMintRecipient: _defaultSender,
            council: _governanceCouncil,
            xanV2Forwarder: address(_xanV2Forwarder)
        });
    }

    function test_forwardCall_reverts_if_the_caller_is_not_the_protocol_adapter() public {
        vm.expectRevert(
            abi.encodeWithSelector(ForwarderBase.UnauthorizedCaller.selector, _defaultSender), address(_xanV2Forwarder)
        );

        // Make the forwarder call but not as the protocol adapter.
        vm.prank(_defaultSender);
        _xanV2Forwarder.forwardCall("");
    }

    function test_forwardCall_forwards_calls_when_called_by_the_protocol_adapter() public {
        // Expect a `Transfer` event reflecting the mint.
        uint256 valueToMint = 123;
        vm.expectEmit(address(_xanV2Proxy));
        emit IERC20.Transfer({from: address(0), to: address(_xanV2Forwarder), value: valueToMint});

        // Make the forwarder call as the protocol adapter.
        vm.prank(address(_mockProtocolAdapter));
        _xanV2Forwarder.forwardCall(abi.encodeCall(XanV2.mint, (_defaultSender, valueToMint)));
    }
}
