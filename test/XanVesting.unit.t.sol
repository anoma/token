// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IXanV2} from "../src/interfaces/IXanV2.sol";
import {IXanVesting} from "../src/interfaces/IXanVesting.sol";
import {XanV2} from "../src/XanV2.sol";
import {XanVesting} from "../src/XanVesting.sol";
import {XanV2Fixture} from "./fixtures/XanV2Fixture.sol";

contract XanVestingUnitTest is XanV2Fixture {
    uint256 internal constant _PRINCIPAL = 1_000_000e18;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _OWNER = makeAddr("owner");
    address internal immutable _RECEIVER = makeAddr("receiver");

    IERC20 internal _xan;
    XanVesting internal _vesting;

    function setUp() public override {
        super.setUp();
        _xan = IERC20(address(_xanV2Proxy));

        _vesting = _deployVesting(_recipients(_ALICE, _PRINCIPAL));
        deal(address(_xan), address(_vesting), _PRINCIPAL);
    }

    function test_constructor_emits_the_VestingScheduled_and_PrincipalAdded_events() public {
        vm.expectEmit();
        emit IXanV2.VestingScheduled({start: _vestingStart, duration: _vestingEnd - _vestingStart});
        vm.expectEmit();
        emit IXanVesting.PrincipalAdded({account: _ALICE, principal: _PRINCIPAL});

        _deployVesting(_recipients(_ALICE, _PRINCIPAL));
    }

    function test_constructor_reverts_on_the_zero_token() public {
        vm.expectRevert(XanVesting.ZeroTokenNotAllowed.selector);
        new XanVesting({
            xanToken: IERC20(address(0)), initialOwner: _OWNER, recipients: _recipients(_ALICE, _PRINCIPAL)
        });
    }

    function test_constructor_reverts_on_an_account_listed_twice() public {
        IXanVesting.Recipient[] memory recipients = new IXanVesting.Recipient[](2);
        recipients[0] = IXanVesting.Recipient({account: _BOB, principal: _PRINCIPAL});
        recipients[1] = IXanVesting.Recipient({account: _BOB, principal: _PRINCIPAL});

        vm.expectRevert(abi.encodeWithSelector(XanVesting.PrincipalAlreadySet.selector, _BOB, _PRINCIPAL));
        _deployVesting(recipients);
    }

    function test_constructor_reverts_on_an_account_with_a_principal_in_the_token() public {
        uint256 tokenPrincipal = _xanV2Proxy.principalOf(_defaultSender);
        assertGt(tokenPrincipal, 0, "the default sender must have a principal in the token");

        vm.expectRevert(abi.encodeWithSelector(XanVesting.PrincipalSetInToken.selector, _defaultSender, tokenPrincipal));
        _deployVesting(_recipients(_defaultSender, _PRINCIPAL));
    }

    function test_constructor_reverts_when_the_recipient_is_the_token() public {
        vm.expectRevert(XanVesting.TokenRecipientNotAllowed.selector);
        _deployVesting(_recipients(address(_xan), _PRINCIPAL));
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
        emit IXanVesting.PrincipalAdded({account: _BOB, principal: _PRINCIPAL});

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));
    }

    function test_addRecipients_reverts_if_the_caller_is_not_the_owner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _BOB));
        vm.prank(_BOB);
        _vesting.addRecipients(_recipients(_BOB, _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_an_account_that_already_has_a_principal() public {
        vm.expectRevert(abi.encodeWithSelector(XanVesting.PrincipalAlreadySet.selector, _ALICE, _PRINCIPAL));
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_ALICE, _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_an_account_with_a_principal_in_the_token() public {
        uint256 tokenPrincipal = _xanV2Proxy.principalOf(_defaultSender);
        assertGt(tokenPrincipal, 0, "the default sender must have a principal in the token");

        vm.expectRevert(abi.encodeWithSelector(XanVesting.PrincipalSetInToken.selector, _defaultSender, tokenPrincipal));
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_defaultSender, _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_the_zero_account() public {
        vm.expectRevert(XanVesting.ZeroAccountNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(0), _PRINCIPAL));
    }

    function test_addRecipients_reverts_when_the_recipient_is_the_vesting_contract() public {
        vm.expectRevert(XanVesting.SelfRecipientNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(_vesting), _PRINCIPAL));
    }

    function test_addRecipients_reverts_when_the_recipient_is_the_token() public {
        vm.expectRevert(XanVesting.TokenRecipientNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(address(_xan), _PRINCIPAL));
    }

    function test_addRecipients_reverts_on_the_zero_principal() public {
        vm.expectRevert(XanVesting.ZeroPrincipalNotAllowed.selector);
        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, 0));
    }

    function test_getRecipients_returns_the_accounts_and_the_principals_in_the_order_they_were_added() public {
        uint256 principalOfBob = _PRINCIPAL / 2;

        vm.prank(_OWNER);
        _vesting.addRecipients(_recipients(_BOB, principalOfBob));

        IXanVesting.Recipient[] memory recipients = _vesting.getRecipients();
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

    function test_unlock_moves_the_vested_amount_from_the_locked_to_the_unlocked_balance() public {
        vm.warp(_vestingMid);
        assertEq(_vesting.unlockableBalanceOf(_ALICE), _PRINCIPAL / 2);

        vm.prank(_ALICE);
        _vesting.unlock();

        assertEq(_vesting.unlockableBalanceOf(_ALICE), 0);
        assertEq(_vesting.unlockedBalanceOf(_ALICE), _PRINCIPAL / 2);
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

        vm.expectRevert(abi.encodeWithSelector(XanVesting.TokenBalanceInsufficient.selector, 0, _PRINCIPAL));
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

    function test_withdraw_transfers_the_surplus() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.prank(_OWNER);
        _vesting.withdraw({receiver: _RECEIVER, value: surplus});

        assertEq(_xan.balanceOf(_RECEIVER), surplus);
        assertEq(_xan.balanceOf(address(_vesting)), _vesting.totalLockedBalance());
    }

    function test_withdraw_emits_the_Withdrawn_event() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectEmit(address(_vesting));
        emit IXanVesting.Withdrawn({receiver: _RECEIVER, value: surplus});

        vm.prank(_OWNER);
        _vesting.withdraw({receiver: _RECEIVER, value: surplus});
    }

    function test_withdraw_reverts_if_the_caller_is_not_the_owner() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _BOB));
        vm.prank(_BOB);
        _vesting.withdraw({receiver: _BOB, value: surplus});
    }

    function test_withdraw_reverts_above_the_surplus() public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);

        vm.expectRevert(abi.encodeWithSelector(XanVesting.SurplusInsufficient.selector, surplus, surplus + 1));
        vm.prank(_OWNER);
        _vesting.withdraw({receiver: _RECEIVER, value: surplus + 1});
    }

    function test_withdraw_reverts_when_the_balance_is_below_the_total_locked_balance() public {
        deal(address(_xan), address(_vesting), _PRINCIPAL / 2);
        assertLt(_xan.balanceOf(address(_vesting)), _vesting.totalLockedBalance(), "the balance must be too low");

        vm.expectRevert(abi.encodeWithSelector(XanVesting.SurplusInsufficient.selector, 0, 1));
        vm.prank(_OWNER);
        _vesting.withdraw({receiver: _RECEIVER, value: 1});
    }

    function testFuzz_withdraw_of_the_whole_surplus_leaves_enough_for_all_unlocks(uint256 unlockTime) public {
        uint256 surplus = _PRINCIPAL / 4;
        deal(address(_xan), address(_vesting), _PRINCIPAL + surplus);
        unlockTime = bound(unlockTime, _vestingStart + 1, _vestingEnd - 1);

        vm.warp(unlockTime);
        vm.prank(_ALICE);
        _vesting.unlock();

        vm.prank(_OWNER);
        _vesting.withdraw({receiver: _RECEIVER, value: surplus});

        vm.warp(_vestingEnd);
        vm.prank(_ALICE);
        _vesting.unlock();

        assertEq(_xan.balanceOf(_ALICE), _PRINCIPAL);
        assertEq(_xan.balanceOf(address(_vesting)), 0);
    }

    function test_constructor_copies_the_vesting_schedule_of_the_token() public view {
        assertEq(_vesting.vestingStart(), _xanV2Proxy.vestingStart());
        assertEq(_vesting.vestingEnd(), _xanV2Proxy.vestingEnd());
    }

    function test_constructor_binds_the_token_and_the_owner() public view {
        assertEq(address(_vesting.XAN_TOKEN()), address(_xanV2Proxy));
        assertEq(_vesting.owner(), _OWNER);
    }

    function test_constructor_adds_the_initial_principals() public view {
        assertEq(_vesting.principalOf(_ALICE), _PRINCIPAL);
        assertEq(_vesting.totalPrincipal(), _PRINCIPAL);
    }

    function _deployVesting(IXanVesting.Recipient[] memory recipients) internal returns (XanVesting vesting) {
        vesting = new XanVesting({xanToken: _xan, initialOwner: _OWNER, recipients: recipients});
    }

    function _recipients(address account, uint256 principal)
        internal
        pure
        returns (IXanVesting.Recipient[] memory recipients)
    {
        recipients = new IXanVesting.Recipient[](1);
        recipients[0] = IXanVesting.Recipient({account: account, principal: principal});
    }
}
