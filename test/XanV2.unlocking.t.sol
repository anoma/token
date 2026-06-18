// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Fixture} from "./fixtures/XanV2Fixture.sol";

contract XanV2UnlockingTest is XanV2Fixture {
    using SafeERC20 for XanV2;

    address internal immutable _OTHER = makeAddr("other");

    function test_lockedBalanceOf_returns_full_principal_at_start() public {
        // `_defaultSender` locked the entire supply in V1 before the upgrade.
        vm.warp(_vestingStart);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);
    }

    function test_unlock_reverts_when_nothing_vested() public {
        vm.warp(_vestingStart);
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _defaultSender), address(_xanV2Proxy));
        _xanV2Proxy.unlock();
    }

    function test_claimableBalanceOf_returns_linear_amount_during_vesting() public {
        vm.warp(_vestingMid);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY / 2);

        // Vesting does not become spendable until it is unlocked.
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);
    }

    function test_unlock_makes_vested_tokens_spendable() public {
        vm.warp(_vestingMid);

        vm.prank(_defaultSender);
        uint256 value = _xanV2Proxy.unlock();
        assertEq(value, Parameters.SUPPLY / 2);

        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), 0);

        // The unlocked tokens can now be transferred; the still-locked ones cannot.
        vm.prank(_defaultSender);
        _xanV2Proxy.safeTransfer(_OTHER, Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.balanceOf(_OTHER), Parameters.SUPPLY / 2);

        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(XanV2.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1),
            address(_xanV2Proxy)
        );
        // We do not use `safeTransfer` here to obtain the expected error `UnlockedBalanceInsufficient` instead of
        // `SafeERC20FailedOperation`.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_OTHER, 1);
    }

    function test_claimableBalanceOf_returns_full_principal_after_duration() public {
        vm.warp(_vestingEnd);
        assertEq(_xanV2Proxy.claimableBalanceOf(_defaultSender), Parameters.SUPPLY);

        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), 0);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), Parameters.SUPPLY);
    }

    function test_unlock_emits_the_Unlocked_event() public {
        vm.warp(_vestingMid);

        vm.expectEmit(address(_xanV2Proxy));
        emit IXanV2.Unlocked({account: _defaultSender, value: Parameters.SUPPLY / 2});

        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();
    }

    function test_unlock_reverts_if_no_new_amount_has_vested() public {
        vm.warp(_vestingMid);

        vm.prank(_defaultSender);
        _xanV2Proxy.unlock();

        // A second unlock at the same timestamp has nothing newly vested to release.
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _defaultSender), address(_xanV2Proxy));
        _xanV2Proxy.unlock();
    }

    function test_unlockedBalanceOf_excludes_the_locked_balance() public {
        // Before vesting the whole principal is locked, so none of the balance is unlocked.
        vm.warp(_vestingStart);
        assertEq(_xanV2Proxy.balanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), Parameters.SUPPLY);
        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), 0);
    }

    function test_transfer_reverts_if_value_exceeds_unlocked_balance() public {
        // Before vesting every token is locked, so even a 1-wei transfer exceeds the unlocked balance.
        vm.warp(_vestingStart);
        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(XanV2.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1),
            address(_xanV2Proxy)
        );
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_OTHER, 1);
    }

    function test_burn_reverts_if_value_exceeds_unlocked_balance() public {
        // Burning routes through the same `_update` gate, so locked tokens cannot be burned.
        vm.warp(_vestingStart);
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1));
        _xanV2Proxy.burn(1);
    }

    function test_burn_burns_unlocked_tokens() public {
        // After full vesting and unlock the entire balance is spendable and therefore burnable.
        vm.warp(_vestingEnd);
        vm.startPrank(_defaultSender);
        _xanV2Proxy.unlock();
        _xanV2Proxy.burn(Parameters.SUPPLY / 2);
        vm.stopPrank();

        assertEq(_xanV2Proxy.balanceOf(_defaultSender), Parameters.SUPPLY / 2);
        assertEq(_xanV2Proxy.totalSupply(), Parameters.SUPPLY / 2);
    }

    function test_vestingStart_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingStart(), _vestingStart);
    }

    function test_vestingEnd_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingEnd(), _vestingEnd);
    }
}
