// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {IXanV2Vesting} from "../src/interfaces/IXanV2Vesting.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanV2Vesting} from "../src/XanV2Vesting.sol";
import {XanV2VestingFixture} from "./fixtures/XanV2VestingFixture.sol";

contract XanV2VestingUnitTest is XanV2VestingFixture {
    address internal immutable _RECEIVER = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        deal(address(_xan), address(_vesting), _PRINCIPAL);
    }

    function test_addRecipients_adds_the_principals() public {
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));

        assertEq(_vesting.principalOf(_BOB), _PRINCIPAL);
    }

    function test_addRecipients_raises_the_total_principal_and_the_total_locked_balance() public {
        uint256 principalOfBob = _PRINCIPAL / 2;

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, principalOfBob));

        assertEq(_vesting.totalPrincipal(), _PRINCIPAL + principalOfBob);
        assertEq(_vesting.totalLockedBalance(), _PRINCIPAL + principalOfBob);
    }

    function test_addRecipients_emits_the_PrincipalAdded_event() public {
        vm.expectEmit(address(_vesting));
        emit IXanV2Vesting.PrincipalAdded({account: _BOB, principal: _PRINCIPAL});

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));
    }

    function test_addRecipients_reverts_if_the_caller_is_not_the_owner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _BOB));
        vm.prank(_BOB);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_an_account_that_already_has_a_principal() public {
        vm.expectRevert(abi.encodeWithSelector(XanV2Vesting.PrincipalAlreadySet.selector, _ALICE, _PRINCIPAL));
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_ALICE, _PRINCIPAL));
    }

    function test_addRecipients_adds_an_account_with_a_principal_in_the_token() public {
        assertGt(_xanV2Proxy.principalOf(_defaultSender), 0, "the default sender must have a principal in the token");

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_defaultSender, _PRINCIPAL));

        assertEq(_vesting.principalOf(_defaultSender), _PRINCIPAL);
    }

    function test_addRecipients_reverts_on_the_zero_account() public {
        vm.expectRevert(XanV2Vesting.ZeroAccountNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(0), _PRINCIPAL));
    }

    function test_addRecipients_reverts_when_the_recipient_is_the_vesting_contract() public {
        vm.expectRevert(XanV2Vesting.SelfRecipientNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(_vesting), _PRINCIPAL));
    }

    function test_addRecipients_reverts_when_the_recipient_is_the_token() public {
        vm.expectRevert(XanV2Vesting.TokenRecipientNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(_xan), _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_the_zero_principal() public {
        vm.expectRevert(XanV2Vesting.ZeroPrincipalNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, 0));
    }

    function test_getRecipients_returns_the_accounts_and_the_principals_in_the_order_they_were_added() public {
        uint256 principalOfBob = _PRINCIPAL / 2;

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, principalOfBob));

        IXanV2Vesting.Recipient[] memory recipients = _vesting.getRecipients();
        assertEq(recipients.length, 2);
        assertEq(recipients[0].account, _ALICE);
        assertEq(recipients[0].principal, _PRINCIPAL);
        assertEq(recipients[1].account, _BOB);
        assertEq(recipients[1].principal, principalOfBob);
    }

    function test_unlock_reverts_when_nothing_has_vested() public {
        vm.warp(_vestingStart);

        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _ALICE));
        vm.prank(_ALICE);
        _vesting.unlock();
    }

    function test_unlock_transfers_the_vested_amount() public {
        vm.warp(_vestingMid);

        vm.prank(_ALICE);
        uint256 value = _vesting.unlock();

        assertEq(value, _PRINCIPAL / 2);
        assertEq(_xan.balanceOf(_ALICE), value);
    }

    function test_unlock_transfers_the_whole_principal_after_the_vesting_end() public {
        vm.warp(_vestingEnd);

        vm.prank(_ALICE);
        assertEq(_vesting.unlock(), _PRINCIPAL);
    }

    function test_unlock_moves_the_vested_amount_from_the_locked_balance_to_the_unlocked_amount() public {
        vm.warp(_vestingMid);
        assertEq(_vesting.unlockableBalanceOf(_ALICE), _PRINCIPAL / 2);

        vm.prank(_ALICE);
        _vesting.unlock();

        assertEq(_vesting.unlockableBalanceOf(_ALICE), 0);
        assertEq(_vesting.unlockedAmountOf(_ALICE), _PRINCIPAL / 2);
        assertEq(_vesting.lockedBalanceOf(_ALICE), _PRINCIPAL - _PRINCIPAL / 2);
    }

    function test_unlock_lowers_the_total_locked_balance_by_the_unlocked_amount() public {
        vm.warp(_vestingMid);

        vm.prank(_ALICE);
        uint256 value = _vesting.unlock();

        assertEq(_vesting.totalLockedBalance(), _PRINCIPAL - value);
        assertEq(_vesting.totalPrincipal(), _PRINCIPAL);
    }

    function test_unlock_emits_the_Unlocked_event() public {
        vm.warp(_vestingMid);

        vm.expectEmit(address(_vesting));
        emit IXanV2.Unlocked({account: _ALICE, value: _PRINCIPAL / 2});

        vm.prank(_ALICE);
        _vesting.unlock();
    }

    function test_unlock_reverts_if_no_new_amount_has_vested() public {
        vm.warp(_vestingMid);

        vm.prank(_ALICE);
        _vesting.unlock();

        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _ALICE));
        vm.prank(_ALICE);
        _vesting.unlock();
    }

    function test_unlock_reverts_if_the_token_balance_is_too_low() public {
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));

        vm.warp(_vestingEnd);
        vm.prank(_ALICE);
        _vesting.unlock();
        assertEq(_xan.balanceOf(address(_vesting)), 0, "the unlock of alice must use up the balance");

        vm.expectRevert(abi.encodeWithSelector(XanV2Vesting.TokenBalanceInsufficient.selector, 0, _PRINCIPAL));
        vm.prank(_BOB);
        _vesting.unlock();
    }

    function testFuzz_unlock_transfers_exactly_the_principal_in_total(uint256 firstUnlockTime) public {
        firstUnlockTime = bound(firstUnlockTime, _vestingStart + 1, _vestingEnd - 1);

        vm.warp(firstUnlockTime);
        vm.prank(_ALICE);
        uint256 firstValue = _vesting.unlock();

        vm.warp(_vestingEnd);
        vm.prank(_ALICE);
        uint256 secondValue = _vesting.unlock();

        assertEq(firstValue + secondValue, _PRINCIPAL);
    }

    function test_withdrawSurplus_transfers_the_surplus() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.prank(_OWNER);
        _vesting.withdrawSurplus({receiver: _RECEIVER, value: surplus});

        assertEq(_xan.balanceOf(_RECEIVER), surplus);
        assertEq(_xan.balanceOf(address(_vesting)), _vesting.totalLockedBalance());
    }

    function test_withdrawSurplus_emits_the_SurplusWithdrawn_event() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectEmit(address(_vesting));
        emit IXanV2Vesting.SurplusWithdrawn({receiver: _RECEIVER, value: surplus});

        vm.prank(_OWNER);
        _vesting.withdrawSurplus({receiver: _RECEIVER, value: surplus});
    }

    function test_withdrawSurplus_reverts_if_the_caller_is_not_the_owner() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _BOB));
        vm.prank(_BOB);
        _vesting.withdrawSurplus({receiver: _BOB, value: surplus});
    }

    function test_withdrawSurplus_reverts_above_the_surplus() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectRevert(abi.encodeWithSelector(XanV2Vesting.SurplusInsufficient.selector, surplus, surplus + 1));
        vm.prank(_OWNER);
        _vesting.withdrawSurplus({receiver: _RECEIVER, value: surplus + 1});
    }

    function test_withdrawSurplus_reverts_when_the_balance_is_below_the_total_locked_balance() public {
        deal(address(_xan), address(_vesting), _PRINCIPAL / 2);
        assertLt(_xan.balanceOf(address(_vesting)), _vesting.totalLockedBalance(), "the balance must be too low");

        vm.expectRevert(abi.encodeWithSelector(XanV2Vesting.SurplusInsufficient.selector, 0, 1));
        vm.prank(_OWNER);
        _vesting.withdrawSurplus({receiver: _RECEIVER, value: 1});
    }

    function testFuzz_withdrawSurplus_leaves_enough_for_all_unlocks(uint256 unlockTime) public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);
        unlockTime = bound(unlockTime, _vestingStart + 1, _vestingEnd - 1);

        vm.warp(unlockTime);
        vm.prank(_ALICE);
        _vesting.unlock();

        vm.prank(_OWNER);
        _vesting.withdrawSurplus({receiver: _RECEIVER, value: surplus});

        vm.warp(_vestingEnd);
        vm.prank(_ALICE);
        _vesting.unlock();

        assertEq(_xan.balanceOf(_ALICE), _PRINCIPAL);
        assertEq(_xan.balanceOf(address(_vesting)), 0);
    }

    function test_totalUnlockableBalance_equals_the_sum_of_the_unlockable_balances() public {
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL / 2));
        vm.warp(_vestingMid);

        assertEq(
            _vesting.totalUnlockableBalance(), _vesting.unlockableBalanceOf(_ALICE) + _vesting.unlockableBalanceOf(_BOB)
        );

        vm.prank(_ALICE);
        _vesting.unlock();

        assertEq(_vesting.totalUnlockableBalance(), _vesting.unlockableBalanceOf(_BOB));
    }

    function testFuzz_totalUnlockableBalance_bounds_the_sum_of_the_unlockable_balances(
        uint256 principalOfBob,
        uint256 unlockTime,
        uint256 readTime
    ) public {
        principalOfBob = bound(principalOfBob, 1, _PRINCIPAL);
        unlockTime = bound(unlockTime, _vestingStart + 1, _vestingEnd);
        readTime = bound(readTime, unlockTime, _vestingEnd);

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, principalOfBob));

        vm.warp(unlockTime);
        vm.prank(_ALICE);
        _vesting.unlock();

        vm.warp(readTime);
        uint256 sum = _vesting.unlockableBalanceOf(_ALICE) + _vesting.unlockableBalanceOf(_BOB);
        uint256 total = _vesting.totalUnlockableBalance();

        assertGe(total, sum, "the total must not be below the sum");
        assertLe(total, sum + _vesting.getRecipients().length, "rounding adds at most 1 wei per recipient");
    }

    /// @dev Starts with Alice only, so that the tests add Bob themselves.
    function _initialRecipients() internal view override returns (IXanV2Vesting.Recipient[] memory recipients) {
        recipients = _recipients(_ALICE, _PRINCIPAL);
    }
}
