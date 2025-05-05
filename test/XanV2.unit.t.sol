// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {ForwarderCalldata} from "@anoma/evm-protocol-adapter/Types.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {MockProtocolAdapter} from "../test/mocks/ProtocolAdapter.m.sol";
import {XanV2} from "../test/mocks/XanV2.m.sol";
import {XanV2Forwarder} from "../test/mocks/XanV2Forwarder.m.sol";

contract XanV2UnitTest is Test {
    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;
    address internal _xanV2Forwarder;
    address internal _defaultSender;
    address internal _other;

    MockProtocolAdapter internal _mockProtocolAdapter = new MockProtocolAdapter();

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();
        _other = address(uint160(1));

        // Deploy proxy and mint tokens for the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initialize, _defaultSender)
            })
        );
        _xanV2Forwarder = address(
            new XanV2Forwarder({
                xanProxy: address(_xanV1Proxy),
                protocolAdapter: address(_mockProtocolAdapter),
                calldataCarrierLogicRef: bytes32(0)
            })
        );

        _xanV2Impl = address(new XanV2());

        _winUpgradeVoteForV2Impl(_xanV1Proxy);

        skip(Parameters.DELAY_DURATION);

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy),
            newImpl: _xanV2Impl,
            data: abi.encodeCall(XanV2.initializeV2, (_xanV2Forwarder))
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    function test_initialize_sets_the_owner() public {
        XanV2 v2Proxy = XanV2(
            Upgrades.deployUUPSProxy({
                contractName: "XanV2.m.sol:XanV2",
                initializerData: abi.encodeCall(XanV2.initialize, (_defaultSender, _xanV2Forwarder))
            })
        );
        assertEq(v2Proxy.owner(), _xanV2Forwarder);
    }

    function test_initializeV2_sets_the_owner() public {
        XanV2 v2ProxyUninitialized;
        {
            // Deploy v1
            XanV1 v1Proxy = XanV1(
                Upgrades.deployUUPSProxy({
                    contractName: "XanV1.sol:XanV1",
                    initializerData: abi.encodeCall(XanV1.initialize, _defaultSender)
                })
            );
            _winUpgradeVoteForV2Impl(v1Proxy);

            // Upgrade v1 to v2 but do not reinitialize.
            UnsafeUpgrades.upgradeProxy({proxy: address(v1Proxy), newImpl: _xanV2Impl, data: ""});
            v2ProxyUninitialized = XanV2(address(v1Proxy));
        }

        // Check that the owner hasn't been set.
        assertEq(v2ProxyUninitialized.owner(), address(0));

        // Reinitialize and expect the owner to be set.
        v2ProxyUninitialized.initializeV2({xanV2Forwarder: _xanV2Forwarder});
        assertEq(v2ProxyUninitialized.owner(), _xanV2Forwarder);
    }

    function test_mint_is_callable_from_the_ProtocolAdapter_via_the_XanV2Forwarder() public {
        uint256 valueToMint = 123;

        ForwarderCalldata memory forwarderCalldata = ForwarderCalldata({
            untrustedForwarder: _xanV2Forwarder,
            input: abi.encodeCall(XanV2.mint, (_other, valueToMint)),
            output: bytes("")
        });

        vm.expectEmit(address(_xanV2Proxy));
        emit IERC20.Transfer({from: address(0), to: _xanV2Forwarder, value: valueToMint});

        _mockProtocolAdapter.executeForwarderCall(forwarderCalldata);
    }

    function test_mint_is_callable_by_pranking_the_XanV2Forwarder() public {
        uint256 valueToMint = 123;

        vm.expectEmit(address(_xanV2Proxy));
        emit IERC20.Transfer({from: address(0), to: _xanV2Forwarder, value: valueToMint});

        // Call as the `XanV2Forwarder` contract.
        vm.prank(_xanV2Forwarder);
        _xanV2Proxy.mint({account: _xanV2Forwarder, value: valueToMint});
    }

    function test_mint_reverts_if_the_caller_is_not_the_XanV2Forwarder() public {
        vm.expectRevert(
            abi.encodeWithSelector(XanV2.OwnableUnauthorizedAccount.selector, _defaultSender), address(_xanV2Proxy)
        );

        // Call without being the `XanV2Forwarder` contract.
        vm.prank(_defaultSender);
        _xanV2Proxy.mint({account: _other, value: 123});
    }

    function test_mint_mints_tokens_for_the_XanV2Forwarder() public {
        uint256 valueToMint = 123;

        ForwarderCalldata memory forwarderCalldata = ForwarderCalldata({
            untrustedForwarder: _xanV2Forwarder,
            input: abi.encodeCall(XanV2.mint, (_other, valueToMint)),
            output: bytes("")
        });
        _mockProtocolAdapter.executeForwarderCall(forwarderCalldata);

        // Check that the forwarder contract receives the minted tokens.
        assertEq(_xanV2Proxy.balanceOf(_xanV2Forwarder), valueToMint);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_xanV2Forwarder), valueToMint);
        assertEq(_xanV2Proxy.lockedBalanceOf(_xanV2Forwarder), 0);

        // Check that `_other` doesn't receive the minted tokens on the EVM side.
        assertEq(_xanV2Proxy.balanceOf(_other), 0);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_other), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_other), 0);
    }

    function test_mint_increases_the_total_supply() public {
        uint256 valueToMint = 123;

        ForwarderCalldata memory forwarderCalldata = ForwarderCalldata({
            untrustedForwarder: _xanV2Forwarder,
            input: abi.encodeCall(XanV2.mint, (_other, valueToMint)),
            output: bytes("")
        });
        _mockProtocolAdapter.executeForwarderCall(forwarderCalldata);

        assertEq(_xanV2Proxy.totalSupply(), Parameters.SUPPLY + valueToMint);
    }

    function _winUpgradeVoteForV2Impl(XanV1 xanV1Proxy) internal {
        vm.startPrank(_defaultSender);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_defaultSender));
        xanV1Proxy.castVote(_xanV2Impl);
        xanV1Proxy.startUpgradeDelay(_xanV2Impl);
        vm.stopPrank();
        skip(Parameters.DELAY_DURATION);
    }
}
