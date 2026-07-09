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

    function test_unlock_reverts_when_nothing_has_vested() public {
        vm.warp(_vestingStart);
        vm.prank(_defaultSender);
        vm.expectRevert(abi.encodeWithSelector(XanV2.NothingToUnlock.selector, _defaultSender), address(_xanV2Proxy));
        _xanV2Proxy.unlock();
    }

    function test_unlock_returns_the_vested_balance() public {
        vm.warp(_vestingMid);
        vm.prank(_defaultSender);
        assertEq(_xanV2Proxy.unlock(), Parameters.SUPPLY / 2);
    }

    function test_unlock_makes_vested_tokens_transferable() public {
        vm.warp(_vestingMid);
        vm.prank(_defaultSender);
        uint256 vested = _xanV2Proxy.unlock();

        vm.prank(_defaultSender);
        _xanV2Proxy.safeTransfer(_OTHER, vested);

        assertEq(_xanV2Proxy.balanceOf(_OTHER), vested);
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

    function testFuzz_lockedBalanceOf_returns_the_locked_balance(uint48 time) public {
        vm.warp(bound(time, _vestingStart + 1, _vestingEnd));

        vm.prank(_defaultSender);
        uint256 unlocked = _xanV2Proxy.unlock();

        assertEq(_xanV2Proxy.lockedBalanceOf(_defaultSender), _xanV2Proxy.balanceOf(_defaultSender) - unlocked);
    }

    function testFuzz_unlockableBalanceOf_returns_the_unlockable_balance(uint48 time) public {
        vm.warp(bound(time, _vestingStart + 1, _vestingEnd));

        uint256 unlockable = _xanV2Proxy.unlockableBalanceOf(_defaultSender);

        vm.prank(_defaultSender);
        uint256 unlocked = _xanV2Proxy.unlock();

        assertEq(unlockable, unlocked);
    }

    function testFuzz_unlockedBalanceOf_returns_the_unlocked_balance(uint48 time) public {
        vm.warp(bound(time, _vestingStart + 1, _vestingEnd));

        vm.prank(_defaultSender);
        uint256 unlocked = _xanV2Proxy.unlock();

        assertEq(_xanV2Proxy.unlockedBalanceOf(_defaultSender), unlocked);
    }

    function testFuzz_transfer_reverts_if_value_exceeds_unlocked_balance(uint48 time) public {
        vm.warp(bound(time, _vestingStart + 1, _vestingEnd));

        vm.prank(_defaultSender);
        uint256 unlocked = _xanV2Proxy.unlock();
        uint256 moreThanUnlocked = unlocked + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                XanV2.UnlockedBalanceInsufficient.selector, _defaultSender, unlocked, moreThanUnlocked
            ),
            address(_xanV2Proxy)
        );
        vm.prank(_defaultSender);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        _xanV2Proxy.transfer(_OTHER, moreThanUnlocked);
    }

    function test_vestingStart_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingStart(), _vestingStart);
    }

    function test_vestingEnd_returns_expected_parameter() public view {
        assertEq(_xanV2Proxy.vestingEnd(), _vestingEnd);
    }
}
