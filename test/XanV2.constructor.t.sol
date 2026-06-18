// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/XanV2.sol";

contract XanV2ConstructorTest is Test {
    // Values distinct from the `Parameters` constants, so the assertions prove the getters read the constructor
    // arguments rather than hard-coded parameters.
    uint48 internal constant _VESTING_START = 1_000_000;
    uint48 internal constant _VESTING_DURATION = 3_000_000;

    address internal immutable _INITIAL_OWNER = makeAddr("owner");

    XanV2 internal _impl;

    function setUp() public {
        _impl = new XanV2({
            initialOwner: _INITIAL_OWNER, vestingStartTimestamp: _VESTING_START, vestingDuration: _VESTING_DURATION
        });
    }

    function test_constructor_disables_initializers_on_the_implementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector, address(_impl));
        _impl.reinitializeFromV1();
    }

    function test_constructor_reverts_if_the_owner_is_the_zero_address() public {
        // The revert happens inside the contract being created, whose address we can predict from this contract's nonce.
        address predictedImpl = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanV2.ZeroOwnerNotAllowed.selector, predictedImpl);
        new XanV2({initialOwner: address(0), vestingStartTimestamp: _VESTING_START, vestingDuration: _VESTING_DURATION});
    }

    function test_constructor_binds_the_initial_owner() public {
        address proxy = UnsafeUpgrades.deployUUPSProxy(address(_impl), abi.encodeCall(XanV2.reinitializeFromV1, ()));

        assertEq(XanV2(proxy).owner(), _INITIAL_OWNER);
    }

    function test_constructor_sets_initialized_to_the_maximal_value() public view {
        bytes32 slot = SlotDerivation.erc7201Slot("openzeppelin.storage.Initializable");
        uint64 initialized = uint64(uint256(vm.load(address(_impl), slot)));

        assertEq(initialized, type(uint64).max);
    }

    function test_constructor_sets_the_vesting_start() public view {
        assertEq(_impl.vestingStart(), _VESTING_START);
    }

    function test_constructor_sets_the_vesting_end() public view {
        assertEq(_impl.vestingEnd(), _VESTING_START + _VESTING_DURATION);
    }
}
