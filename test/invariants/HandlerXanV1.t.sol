// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {XanV1} from "src/XanV1.sol";

contract XanV1Handler is Test {
    XanV1 public token;
    address public initialHolder;

    address[] public actors;
    mapping(address => bool) internal isActor;

    uint256 public sum;

    // Valid implementation addresses for testing
    address[5] public validImpls = [address(0x1111), address(0x2222), address(0x3333), address(0x4444), address(0x5555)];

    // State tracking for invariants
    mapping(address => mapping(address => uint256)) internal previousVotes; // voter => impl => votes
    mapping(address => uint256) internal previousLockedBalances;
    uint256 internal previousLockedSupply;

    constructor(XanV1 _token, address _initialHolder) {
        token = _token;
        initialHolder = _initialHolder;
        _addActor(_initialHolder);
        sum = 0;
    }

    function _addActor(address a) internal {
        if (!isActor[a]) {
            isActor[a] = true;
            actors.push(a);
        }
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    // Functions to access state tracking for invariants
    function getPreviousVotes(address voter, address impl) external view returns (uint256) {
        return previousVotes[voter][impl];
    }

    function getPreviousLockedBalance(address account) external view returns (uint256) {
        return previousLockedBalances[account];
    }

    function getPreviousLockedSupply() external view returns (uint256) {
        return previousLockedSupply;
    }

    function updateStateTracking() public {
        // Update previous locked supply
        previousLockedSupply = token.lockedSupply();

        // Update previous locked balances for all actors
        for (uint256 i = 0; i < actors.length; i++) {
            previousLockedBalances[actors[i]] = token.lockedBalanceOf(actors[i]);
        }
    }

    function updateStateTrackingFor(address account) public {
        // Update previous locked supply
        previousLockedSupply = token.lockedSupply();

        // Update previous locked balance for specific account
        previousLockedBalances[account] = token.lockedBalanceOf(account);
    }

    function updateStateTrackingFor(address account1, address account2) public {
        // Update previous locked supply
        previousLockedSupply = token.lockedSupply();

        // Update previous locked balances for specific accounts
        previousLockedBalances[account1] = token.lockedBalanceOf(account1);
        previousLockedBalances[account2] = token.lockedBalanceOf(account2);
    }

    function airdrop(address to, uint256 amount) external {
        // bounding to non-zero addresses, to avoid unnecessary reverts
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        _addActor(to);
        uint256 unlocked = token.unlockedBalanceOf(initialHolder);
        amount = bound(amount, 0, unlocked);
        vm.prank(initialHolder);
        token.transfer(to, amount);
    }

    function transfer(address from, address to, uint256 amount) external {
        from = address(uint160(bound(uint160(from), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        _addActor(from);
        _addActor(to);
        uint256 unlocked = token.unlockedBalanceOf(from);
        amount = bound(amount, 0, unlocked);
        vm.prank(from);
        token.transfer(to, amount);
    }

    function lock(address who, uint256 amount) external {
        _addActor(who);
        uint256 unlocked = token.unlockedBalanceOf(who);
        amount = bound(amount, 0, unlocked);

        // Update state tracking for the account locking tokens
        updateStateTrackingFor(who);

        vm.prank(who);
        token.lock(amount);
    }

    function transferAndLock(address from, address to, uint256 amount) external {
        from = address(uint160(bound(uint160(from), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        _addActor(from);
        _addActor(to);
        uint256 unlocked = token.unlockedBalanceOf(from);
        amount = bound(amount, 0, unlocked);

        // Update state tracking for accounts involved in transferAndLock
        updateStateTrackingFor(from, to);

        vm.prank(from);
        token.transferAndLock(to, amount);
    }

    function castVote(address who, uint256 implIndex) external {
        who = address(uint160(bound(uint160(who), 1, type(uint160).max)));
        _addActor(who);

        // Restrict to only valid implementation addresses
        implIndex = bound(implIndex, 0, validImpls.length - 1);
        address impl = validImpls[implIndex];

        // Track previous vote count for this voter-implementation pair
        previousVotes[who][impl] = token.getVotes(who, impl);

        // Ensure the voter has at least 1 unit locked to avoid revert on zero votes.
        if (token.lockedBalanceOf(who) == 0) {
            uint256 airdropable = token.unlockedBalanceOf(initialHolder);
            if (airdropable == 0) return; // nothing to do
            uint256 amount = 1;
            vm.startPrank(initialHolder);
            token.transfer(who, amount);
            vm.stopPrank();

            vm.prank(who);
            token.lock(amount);
        }

        vm.prank(who);
        token.castVote(impl);
    }

    function scheduleVoterBodyUpgrade() external {
        token.scheduleVoterBodyUpgrade();
    }

    function cancelVoterBodyUpgrade() external {
        // Respect the waiting period by advancing time to the scheduled end time if needed.
        (, uint48 endTime) = token.scheduledVoterBodyUpgrade();
        if (endTime == 0) return; // nothing scheduled
        if (block.timestamp < endTime) {
            vm.warp(endTime);
        }

        // Update state tracking before cancellation
        // This is done to prove that certain variants hold
        updateStateTracking();

        token.cancelVoterBodyUpgrade();
    }

    function scheduleCouncilUpgrade(uint256 implIndex) external {
        // Council-only; prank as council.
        address council = token.governanceCouncil();

        // Restrict to only valid implementation addresses
        implIndex = bound(implIndex, 0, validImpls.length - 1);
        address impl = validImpls[implIndex];

        vm.prank(council);
        token.scheduleCouncilUpgrade(impl);
    }

    function cancelCouncilUpgrade() external {
        // Council-only; no waiting period required for cancellation.
        address council = token.governanceCouncil();

        // Update state tracking before cancellation
        updateStateTracking();

        vm.prank(council);
        token.cancelCouncilUpgrade();
    }

    function vetoCouncilUpgrade() external {
        // Update state tracking before vetoing
        updateStateTracking();
        // Anyone can attempt; requires quorum/min-locked reached or will revert.
        token.vetoCouncilUpgrade();
    }
}
