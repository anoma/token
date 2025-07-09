// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1LockingTest is Test {
    address internal constant _COUNCIL = address(uint160(1));
    address internal constant _RECEIVER = address(uint160(2));

    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _COUNCIL))
            })
        );
    }

    function test_lock_locks_incrementally() public {
        vm.startPrank(_defaultSender);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);
        _xanProxy.lock(1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 1);
        _xanProxy.lock(1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 2);
        vm.stopPrank();
    }

    function test_lock_emits_the_Locked_event() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.Locked({account: _defaultSender, value: valueToLock});

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);
    }

    function test_transfer_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());

        uint256 unlocked = _xanProxy.unlockedBalanceOf(_defaultSender);
        assertEq(unlocked, 0);

        uint256 toTransfer = 1;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, unlocked, toTransfer),
            address(_xanProxy)
        );
        _xanProxy.transfer({to: _RECEIVER, value: 1});
    }

    function test_transfer_transfers_tokens() public {
        uint256 supply = _xanProxy.totalSupply();
        assertEq(_xanProxy.balanceOf(_defaultSender), supply);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), supply);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);

        vm.prank(_defaultSender);
        _xanProxy.transfer({to: _RECEIVER, value: 1});

        assertEq(_xanProxy.balanceOf(_defaultSender), supply - 1);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), supply - 1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);
    }

    function test_transfer_emits_the_Transfer_event() public {
        vm.expectEmit(address(_xanProxy));
        emit IERC20.Transfer({from: _defaultSender, to: _RECEIVER, value: 1});

        vm.prank(_defaultSender);
        _xanProxy.transfer({to: _RECEIVER, value: 1});
    }

    function test_transferAndLock_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());

        uint256 unlocked = _xanProxy.unlockedBalanceOf(_defaultSender);
        assertEq(unlocked, 0);

        uint256 toTransfer = 1;

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, unlocked, toTransfer),
            address(_xanProxy)
        );
        _xanProxy.transferAndLock({to: _RECEIVER, value: 1});
    }

    function test_transfer_transfers_and_locks_tokens() public {
        uint256 supply = _xanProxy.totalSupply();

        assertEq(_xanProxy.balanceOf(_defaultSender), supply);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), supply);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 0);

        vm.prank(_defaultSender);
        _xanProxy.transferAndLock({to: _RECEIVER, value: 1});

        assertEq(_xanProxy.balanceOf(_defaultSender), supply - 1);
        assertEq(_xanProxy.unlockedBalanceOf(_defaultSender), supply - 1);
        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), 0);

        assertEq(_xanProxy.balanceOf(_RECEIVER), 1);
        assertEq(_xanProxy.unlockedBalanceOf(_RECEIVER), 0);
        assertEq(_xanProxy.lockedBalanceOf(_RECEIVER), 1);
    }

    function test_burn_reverts_on_insufficient_unlocked_tokens() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.balanceOf(_defaultSender));

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.UnlockedBalanceInsufficient.selector, _defaultSender, 0, 1), address(_xanProxy)
        );
        _xanProxy.burn(1);
        vm.stopPrank();
    }

    function test_burn_burns_unlocked_tokens() public {
        uint256 balance = _xanProxy.balanceOf(_defaultSender);
        assertEq(balance, _xanProxy.totalSupply());

        vm.startPrank(_defaultSender);
        _xanProxy.burn(balance);
        vm.stopPrank();

        assertEq(_xanProxy.totalSupply(), 0);
    }

    function test_lockedBalanceOf_returns_the_locked_balance() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(_xanProxy.lockedBalanceOf(_defaultSender), valueToLock);
    }

    function test_unlockedBalanceOf_returns_the_unlocked_balance() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;
        uint256 expectedUnlockedValue = _xanProxy.totalSupply() - valueToLock;

        vm.prank(_defaultSender);
        _xanProxy.lock(valueToLock);

        assertEq(expectedUnlockedValue, _xanProxy.unlockedBalanceOf(_defaultSender));
    }

    function test_lockedSupply_returns_the_locked_supply() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.startPrank(_defaultSender);

        _xanProxy.lock(valueToLock);
        assertEq(_xanProxy.lockedSupply(), valueToLock);

        _xanProxy.lock(valueToLock);
        assertEq(_xanProxy.lockedSupply(), 2 * valueToLock);

        _xanProxy.lock(valueToLock);
        assertEq(_xanProxy.lockedSupply(), 3 * valueToLock);
    }

    function testFuzz_lockedBalanceOf_and_unlockedBalanceOf_sum_to_balanceOf(address owner) public view {
        assertEq(_xanProxy.lockedBalanceOf(owner) + _xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_lockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.lockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function test_unlockedBalanceOf_is_bound_by_balanceOf(address owner) public view {
        assertLe(_xanProxy.unlockedBalanceOf(owner), _xanProxy.balanceOf(owner));
    }

    function invariant_lockedBalance() public view {
        assertLe(_xanProxy.lockedSupply(), _xanProxy.totalSupply());
    }
}
