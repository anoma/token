// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../../src/XanV2.sol";

contract XanV2Handler is Test {
    using SafeERC20 for XanV2;

    XanV2 public token;
    address public initialHolder;

    // ============ GHOST VARIABLES (for invariant tracking) ============

    address[] internal _actors;
    mapping(address actor => bool isActor) internal _isActor;

    constructor(XanV2 _token, address _initialHolder) {
        token = _token;
        initialHolder = _initialHolder;

        _addActor(_initialHolder);
        _addActor(makeAddr("voter1"));
        _addActor(makeAddr("voter2"));
        _addActor(makeAddr("voter3"));
    }

    // ============ FUZZED BUSINESS LOGIC FUNCTIONS ============

    function delegateToSelf(uint256 actorSeed) external {
        address actor = _actorAt(actorSeed);

        vm.prank(actor);
        token.delegate(actor);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actorAt(fromSeed);
        address to = _actorAt(toSeed);

        // Only the unlocked balance is transferable; bounding to it keeps the call from reverting.
        amount = bound(amount, 0, token.unlockedBalanceOf(from));

        vm.prank(from);
        token.safeTransfer(to, amount);
    }

    function unlock(uint256 actorSeed) external {
        address actor = _actorAt(actorSeed);

        // `unlock` reverts when nothing has vested since the last unlock; skip in that case.
        if (token.unlockableBalanceOf(actor) == 0) {
            return;
        }

        vm.prank(actor);
        token.unlock();
    }

    function advanceTime(uint256 secondsToAdd) external {
        // Sweep the sequence through the before/during/after vesting phases.
        secondsToAdd = bound(secondsToAdd, 0, 14 days);
        vm.warp(block.timestamp + secondsToAdd);
    }

    // ============ GETTER FUNCTIONS ============

    function getActors() external view returns (address[] memory arr) {
        arr = _actors;
    }

    // ============ HELPER FUNCTIONS ============

    function _addActor(address a) internal {
        if (!_isActor[a]) {
            _isActor[a] = true;
            _actors.push(a);
        }
    }

    function _actorAt(uint256 seed) internal view returns (address actor) {
        actor = _actors[bound(seed, 0, _actors.length - 1)];
    }
}
