// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {XanV1} from "src/XanV1.sol";

contract XanV1Handler is Test {
    XanV1 public token;
    address public initialHolder;

    // ============ GHOST VARIABLES (for invariant tracking) ============
    address[] public actors;
    mapping(address => bool) internal isActor;

    // Valid implementation addresses for testing
    address[5] public validImpls = [address(0x1111), address(0x2222), address(0x3333), address(0x4444), address(0x5555)];

    mapping(address => mapping(address => uint256)) internal previousVotes; // voter => impl => votes
    mapping(address => uint256) internal previousLockedBalances;
    uint256 internal previousLockedSupply;

    constructor(XanV1 _token, address _initialHolder) {
        token = _token;
        initialHolder = _initialHolder;
        _addActor(_initialHolder);
    }

    // ============ HELPER FUNCTIONS ============

    function _addActor(address a) internal {
        if (!isActor[a]) {
            isActor[a] = true;
            actors.push(a);
        }
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function getValidImpls() external view returns (address[5] memory) {
        return validImpls;
    }

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

        // Update previous locked balances and votes for all actors
        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            previousLockedBalances[actor] = token.lockedBalanceOf(actor);
            // Capture votes across all implementations
            for (uint256 j = 0; j < validImpls.length; j++) {
                previousVotes[actor][validImpls[j]] = token.getVotes(actor, validImpls[j]);
            }
        }
    }

    function updateStateTrackingFor(address account) public {
        // Update previous locked supply
        previousLockedSupply = token.lockedSupply();

        // Update previous locked balance and votes for a specific account
        previousLockedBalances[account] = token.lockedBalanceOf(account);
        for (uint256 j = 0; j < validImpls.length; j++) {
            previousVotes[account][validImpls[j]] = token.getVotes(account, validImpls[j]);
        }
    }

    function updateStateTrackingFor(address account1, address account2) public {
        // Update previous locked supply
        previousLockedSupply = token.lockedSupply();

        // Update state for account1
        previousLockedBalances[account1] = token.lockedBalanceOf(account1);
        for (uint256 j = 0; j < validImpls.length; j++) {
            previousVotes[account1][validImpls[j]] = token.getVotes(account1, validImpls[j]);
        }

        // Update state for account2
        previousLockedBalances[account2] = token.lockedBalanceOf(account2);
        for (uint256 j = 0; j < validImpls.length; j++) {
            previousVotes[account2][validImpls[j]] = token.getVotes(account2, validImpls[j]);
        }
    }

    // ============ FUZZED BUSINESS LOGIC FUNCTIONS ============

    function airdrop(address to, uint256 amount) external {
        // bounding to non-zero addresses, to avoid unnecessary reverts
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        _addActor(to);
        uint256 unlocked = token.unlockedBalanceOf(initialHolder);
        amount = bound(amount, 0, unlocked);
        updateStateTrackingFor(initialHolder, to);
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
        updateStateTrackingFor(from, to);
        vm.prank(from);
        token.transfer(to, amount);
    }

    function lock(address who, uint256 amount) external {
        _addActor(who);
        uint256 unlocked = token.unlockedBalanceOf(who);
        amount = bound(amount, 0, unlocked);

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

        updateStateTrackingFor(who);

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
        updateStateTracking();
        token.scheduleVoterBodyUpgrade();
    }

    function cancelVoterBodyUpgrade() external {
        // Respect the waiting period by advancing time to the scheduled end time if needed.
        (, uint48 endTime) = token.scheduledVoterBodyUpgrade();
        if (endTime == 0) return; // nothing scheduled
        if (block.timestamp < endTime) {
            vm.warp(endTime + 1);
        }

        updateStateTracking();

        token.cancelVoterBodyUpgrade();
    }

    function scheduleCouncilUpgrade(uint256 implIndex) external {
        // Council-only; prank as council.
        address council = token.governanceCouncil();

        implIndex = bound(implIndex, 0, validImpls.length - 1);
        address impl = validImpls[implIndex];

        updateStateTracking();

        vm.prank(council);
        token.scheduleCouncilUpgrade(impl);
    }

    function cancelCouncilUpgrade() external {
        // Council-only; no waiting period required for cancellation.
        address council = token.governanceCouncil();

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
