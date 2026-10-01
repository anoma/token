// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";

contract XanV2VestingConstructorTest is Test {
    // Values distinct from the `Parameters` constants, so the assertions prove that the getters read the schedule of
    // the token.
    uint48 internal constant _VESTING_START = 1_000_000;
    uint48 internal constant _VESTING_DURATION = 3_000_000;

    IERC20 internal _token;
    XanV2Vesting internal _impl;

    function setUp() public {
        // The constructor reads only the schedule of the token, so a `XanV2` implementation stands in for the proxy.
        _token = IERC20(
            address(
                new XanV2({
                    initialProxyOwner: makeAddr("owner"),
                    vestingStartTimestamp: _VESTING_START,
                    vestingDuration: _VESTING_DURATION
                })
            )
        );
        _impl = new XanV2Vesting({xanToken: _token});
    }

    function test_constructor_disables_initializers_on_the_implementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector, address(_impl));
        _impl.initialize({initialOwner: makeAddr("owner"), recipients: new IXanV2Vesting.Recipient[](0)});
    }

    function test_constructor_reverts_if_the_token_is_the_zero_address() public {
        address predictedImpl = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(XanV2Vesting.ZeroTokenNotAllowed.selector, predictedImpl);
        new XanV2Vesting({xanToken: IERC20(address(0))});
    }

    function test_constructor_sets_initialized_to_the_maximal_value() public view {
        bytes32 slot = SlotDerivation.erc7201Slot("openzeppelin.storage.Initializable");
        uint64 initialized = uint64(uint256(vm.load(address(_impl), slot)));

        assertEq(initialized, type(uint64).max);
    }

    function test_constructor_binds_the_token() public view {
        assertEq(address(_impl.XAN_TOKEN()), address(_token));
    }

    function test_constructor_copies_the_vesting_start_of_the_token() public view {
        assertEq(_impl.vestingStart(), _VESTING_START);
    }

    function test_constructor_copies_the_vesting_end_of_the_token() public view {
        assertEq(_impl.vestingEnd(), _VESTING_START + _VESTING_DURATION);
    }
}
