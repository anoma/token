// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {XanV1} from "src/XanV1.sol";
import {XanV1Handler} from "./HandlerXanV1.t.sol";

contract XanV1Invariants is StdInvariant, Test {
    XanV1 public token;
    XanV1Handler public handler;

    address internal alice = makeAddr("alice");
    address internal council = makeAddr("council");

    function setUp() public {
        // Deploy implementation
        XanV1 impl = new XanV1();
        // Deploy proxy with initializer
        bytes memory init = abi.encodeWithSelector(XanV1.initializeV1.selector, alice, council);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        token = XanV1(payable(address(proxy)));

        handler = new XanV1Handler(token, alice);

        // Register the handler for invariant fuzzing
        targetContract(address(handler));
    }
    // PS-1: Locked balances never exceed total balances for any address
    // Invariant: for all seen actors:
    // - lockedBalance <= balance
    // - unlockedBalance == balance - lockedBalance
    // - sum(lockedBalances) == lockedSupply

    function invariant_lockedAccountingHolds() public view {
        address[] memory actors = handler.getActors();
        uint256 sumLocked = 0;

        for (uint256 i = 0; i < actors.length; i++) {
            uint256 balance = token.balanceOf(actors[i]);
            uint256 locked = token.lockedBalanceOf(actors[i]);
            uint256 unlocked = token.unlockedBalanceOf(actors[i]);

            assertLe(locked, balance, "locked > balance");
            assertEq(unlocked, balance - locked, "unlocked != balance - locked");

            sumLocked += locked;
        }

        assertEq(sumLocked, token.lockedSupply(), "sum(locked) != lockedSupply");
    }

    // PS-2: locked token transfer immutability =>
    // Locked balances can never decrease (be transferred) for any address
    function invariant_lockedBalanceMonotonicity() public view {
        address[] memory actors = handler.getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address account = actors[i];
            uint256 currentLocked = token.lockedBalanceOf(account);
            uint256 previousLocked = handler.getPreviousLockedBalance(account);

            assertGe(currentLocked, previousLocked, "locked balance decreased for account");
        }
    }

    // PS-4: Vote monotonicity
    // Individual vote counts can only increase (never decrease) for any voter-implementation pair
    function invariant_voteMonotonicity() public view {
        address[] memory actors = handler.getActors();
        address[5] memory validImpls = handler.getValidImpls();

        for (uint256 i = 0; i < actors.length; i++) {
            address voter = actors[i];

            // Check all valid implementation addresses to verify monotonicity
            for (uint256 j = 0; j < validImpls.length; j++) {
                address impl = validImpls[j];
                uint256 currentVotes = token.getVotes(voter, impl);
                uint256 previousVotes = handler.getPreviousVotes(voter, impl);

                assertGe(currentVotes, previousVotes, "vote count decreased for voter-implementation pair");
            }
        }
    }

    // PS-5: Upgrade mutual exclusion — never both scheduled at once
    function invariant_upgradeMutualExclusion() public view {
        (address vImpl, uint48 vEnd) = token.scheduledVoterBodyUpgrade();
        (address cImpl, uint48 cEnd) = token.scheduledCouncilUpgrade();
        bool voterScheduled = (vImpl != address(0) && vEnd != 0);
        bool councilScheduled = (cImpl != address(0) && cEnd != 0);

        assertTrue(!(voterScheduled && councilScheduled), "both voter and council scheduled");
    }

    //PS-9 (upgrade cancellation token persistence) is implicitly proved by invariant tests above
}
