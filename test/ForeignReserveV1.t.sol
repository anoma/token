// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {ForeignReserveV1, IForeignReserveV1} from "../src/ForeignReserveV1.sol";

import {MockOwner} from "./mocks/Owner.m.sol";
import {MockTarget} from "./mocks/Target.m.sol";

contract ForeignReserveV1Test is Test {
    address internal constant _OTHER = address(uint160(1));

    ForeignReserveV1 internal _reserve;
    address internal _target;
    address internal _owner;

    function setUp() public {
        _reserve = ForeignReserveV1(
            payable(
                Upgrades.deployUUPSProxy({contractName: "ForeignReserveV1.sol:ForeignReserveV1", initializerData: ""})
            )
        );

        _owner = address(new MockOwner(_reserve));

        _reserve.initializeV1({initialOwner: _owner});

        _target = address(new MockTarget());
    }

    function test_execute_reverts_if_not_called_by_the_owner() public {
        vm.prank(_OTHER);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _OTHER), address(_reserve)
        );
        _reserve.execute({target: _target, value: 0, data: ""});
    }

    function test_execute_reverts_if_the_target_contract_reverts() public {
        bytes memory revertingCall = abi.encodeCall(MockTarget.revertingCall, ());

        vm.prank(_owner);
        vm.expectRevert(MockTarget.CallReverted.selector, _target);
        _reserve.execute({target: _target, value: 0, data: revertingCall});
    }

    function test_execute_reverts_on_reentrancy() public {
        bytes memory reentrantCall = abi.encodeCall(ForeignReserveV1.execute, (address(this), 0, ""));
        bytes memory call = abi.encodeCall(MockOwner.executeOnForeignReserve, (_owner, 0, reentrantCall));

        vm.prank(_owner);
        vm.expectRevert(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector, address(_reserve));
        _reserve.execute({target: _owner, value: 0, data: call});
    }

    function test_execute_without_eth() public {
        bytes memory data = abi.encodeCall(MockTarget.ping, ());

        vm.prank(_owner);
        vm.expectEmit(_target);
        emit MockTarget.Called({from: address(_reserve), value: 0, data: data});

        bytes memory result = _reserve.execute({target: _target, value: 0, data: data});

        // Decode the result
        assertEq(abi.decode(result, (string)), "pong");
    }

    function test_execute_with_eth() public {
        uint256 value = 0.05 ether;
        bytes memory data = abi.encodeCall(MockTarget.ping, ());

        vm.deal(_owner, value);

        vm.prank(_owner);
        vm.expectEmit(_target);
        emit MockTarget.Called({from: address(_reserve), value: value, data: data});
        bytes memory result =
            _reserve.execute{value: value}({target: _target, value: value, data: abi.encodeCall(MockTarget.ping, ())});

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
        assertEq(_reserve.owner(), _owner);
    }
}
