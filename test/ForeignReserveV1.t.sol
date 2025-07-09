// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {ForeignReserveV1, IForeignReserveV1} from "../src/ForeignReserveV1.sol";

import {MockCallTarget} from "./mocks/CallTarget.m.sol";

contract ForeignReserveV1Test is Test {
    address internal constant _OWNER = address(uint160(1));
    address internal constant _OTHER = address(uint160(2));

    ForeignReserveV1 internal _reserve;
    MockCallTarget internal _target;

    function setUp() public {
        _reserve = ForeignReserveV1(
            payable(
                Upgrades.deployUUPSProxy({
                    contractName: "ForeignReserveV1.sol:ForeignReserveV1",
                    initializerData: abi.encodeCall(ForeignReserveV1.initializeV1, (_OWNER))
                })
            )
        );

        _target = new MockCallTarget();
    }

    function test_execute_reverts_if_not_called_by_the_owner() public {
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _OTHER), address(_reserve)
        );
        _reserve.execute({target: address(_target), value: 0, data: ""});
    }

    function test_execute_without_eth() public {
        bytes memory data = abi.encodeCall(MockCallTarget.ping, ());

        vm.prank(_OWNER);
        vm.expectEmit(address(_target));
        emit MockCallTarget.Called({from: address(_reserve), value: 0, data: data});

        bytes memory result = _reserve.execute({target: address(_target), value: 0, data: data});

        // Decode the result
        assertEq(abi.decode(result, (string)), "pong");
    }

    function test_execute_with_eth() public {
        uint256 value = 0.05 ether;
        bytes memory data = abi.encodeCall(MockCallTarget.ping, ());

        vm.deal(_OWNER, value);

        vm.prank(_OWNER);
        vm.expectEmit(address(_target));
        emit MockCallTarget.Called({from: address(_reserve), value: value, data: data});
        bytes memory result = _reserve.execute{value: value}({
            target: address(_target),
            value: value,
            data: abi.encodeCall(MockCallTarget.ping, ())
        });

        // Decode the result
        assertEq(abi.decode(result, (string)), "pong");
    }

    function test_receive_emits_NativeTokenReceived() public {
        uint256 value = 0.05 ether;

        vm.expectEmit(address(_reserve));
        emit IForeignReserveV1.NativeTokenReceived(address(this), value);

        (bool success,) = address(_reserve).call{value: value}("");
        assertTrue(success);
    }

    function test_initialize_set_the_initial_owner() public view {
        assertEq(_reserve.owner(), _OWNER);
    }
}
