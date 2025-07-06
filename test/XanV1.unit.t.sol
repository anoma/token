// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1UnitTest is Test {
    address internal constant _IMPL = address(uint160(1));
    address internal constant _OTHER_IMPL = address(uint160(2));
    address internal constant _RECEIVER = address(uint160(3));

    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, _defaultSender)
            })
        );
    }

    function test_implementation_points_to_the_correct_implementation() public {
        address impl = address(new XanV1());

        XanV1 proxy = XanV1(
            UnsafeUpgrades.deployUUPSProxy({
                impl: impl,
                initializerData: abi.encodeCall(XanV1.initializeV1, _defaultSender)
            })
        );

        assertEq(proxy.implementation(), impl);
    }

    function test_initialize_mints_the_supply_for_the_specified_owner() public {
        XanV1 uninitializedProxy =
            XanV1(Upgrades.deployUUPSProxy({contractName: "XanV1.sol:XanV1", initializerData: ""}));

        assertEq(uninitializedProxy.unlockedBalanceOf(_defaultSender), 0);

        uninitializedProxy.initializeV1({initialMintRecipient: _defaultSender});

        assertEq(uninitializedProxy.unlockedBalanceOf(_defaultSender), uninitializedProxy.totalSupply());
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

    function test_castVote_emits_the_VoteCast_event() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteCast({voter: _defaultSender, implementation: _IMPL, value: valueToLock});

        _xanProxy.castVote(_IMPL);
        vm.stopPrank();
    }

    function test_castVote_reverts_if_zero_tokens_have_been_locked() public {
        vm.prank(_defaultSender);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);
    }

    function test_castVote_ranks_an_implementation_on_first_vote() public {
        // Check that no implementation has rank 0.
        uint48 rank = 0;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 0, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);

        // Lock, vote, and check that there is an implementation with rank 0.
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();
        assertEq(_IMPL, _xanProxy.proposedImplementationByRank(rank));

        // Check that no implementation has rank 1.
        rank = 1;
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationRankNonExistent.selector, 1, rank), address(_xanProxy)
        );
        _xanProxy.proposedImplementationByRank(rank);
    }

    function test_castVote_reverts_if_the_votum_has_already_been_casted() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 3;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, valueToLock),
            address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);

        vm.stopPrank();
    }

    function test_castVote_reverts_if_caller_has_no_locked_tokens() public {
        vm.prank(_defaultSender);
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.LockedBalanceInsufficient.selector, _defaultSender, 0), address(_xanProxy)
        );
        _xanProxy.castVote(_IMPL);
    }

    function test_castVote_increases_votes_if_more_tokens_have_been_locked() public {
        uint256 firstLockValue = _xanProxy.totalSupply() / 3;
        uint256 secondLockValue = _xanProxy.totalSupply() - firstLockValue;

        vm.startPrank(_defaultSender);

        _xanProxy.lock(firstLockValue);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.totalVotes(_IMPL), firstLockValue);

        _xanProxy.lock(secondLockValue);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.totalVotes(_IMPL), firstLockValue + secondLockValue);

        vm.stopPrank();
    }

    function test_castVote_sets_the_votes_of_the_caller_to_the_locked_balance() public {
        uint256 firstLockValue = _xanProxy.totalSupply() / 3;
        uint256 secondLockValue = _xanProxy.totalSupply() - firstLockValue;

        vm.startPrank(_defaultSender);
        assertEq(_xanProxy.votum(_IMPL), 0);

        _xanProxy.lock(firstLockValue);
        _xanProxy.castVote(_IMPL);

        assertEq(_xanProxy.votum(_IMPL), firstLockValue);

        _xanProxy.lock(secondLockValue);
        _xanProxy.castVote(_IMPL);

        assertEq(_xanProxy.votum(_IMPL), firstLockValue + secondLockValue);
        vm.stopPrank();
    }

    function test_revokeVote_emits_the_VoteRevoked_event() public {
        uint256 valueToLock = _xanProxy.totalSupply() / 2;

        vm.startPrank(_defaultSender);
        _xanProxy.lock(valueToLock);
        _xanProxy.castVote(_IMPL);

        vm.expectEmit(address(_xanProxy));
        emit IXanV1.VoteRevoked({voter: _defaultSender, implementation: _IMPL, value: valueToLock});

        _xanProxy.revokeVote(_IMPL);
        vm.stopPrank();
    }

    function test_revokeVote_sets_the_votes_of_the_caller_to_zero() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.votum(_IMPL), _xanProxy.totalSupply());

        _xanProxy.revokeVote(_IMPL);
        assertEq(_xanProxy.votum(_IMPL), 0);
        vm.stopPrank();
    }

    function test_revokeVote_subtracts_the_old_votum_from_the_total_votes() public {
        uint256 votesReceiver = _xanProxy.totalSupply() / 3;
        uint256 votesDefaultSender = _xanProxy.totalSupply() - votesReceiver;

        // Send tokens to `_RECEIVER` from `_defaultSender` lock them.
        vm.startPrank(_defaultSender);
        _xanProxy.transferAndLock({to: _RECEIVER, value: votesReceiver});

        // Vote as `_defaultSender`.
        _xanProxy.lock(votesDefaultSender);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        // Vote as `_RECEIVER`.
        vm.prank(_RECEIVER);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.totalVotes(_IMPL), votesDefaultSender + votesReceiver);

        // Revoke the vote as `_defaultSender` and
        vm.startPrank(_defaultSender);
        _xanProxy.revokeVote(_IMPL);

        // Check that the total votes are correct.
        assertEq(_xanProxy.totalVotes(_IMPL), votesReceiver);
        vm.stopPrank();
    }

    function test_revokeVote_reverts_if_the_voter_has_not_voted_on_the_proposal() public {
        vm.expectRevert(
            abi.encodeWithSelector(XanV1.NoVotesToRevoke.selector, _defaultSender, _IMPL), address(_xanProxy)
        );
        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_IMPL);
    }

    function test_startUpgradeDelay_starts_the_delay_if_locked_supply_and_quorum_are_met_and_the_impl_is_ranked_best()
        public
    {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        assertGe(_xanProxy.lockedSupply(), Parameters.MIN_LOCKED_SUPPLY);

        assertGt(_xanProxy.totalVotes(_IMPL), _xanProxy.calculateQuorumThreshold());
        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);

        uint48 currentTime = Time.timestamp();
        _xanProxy.startUpgradeDelay(_IMPL);

        assertEq(_xanProxy.delayEndTime(), currentTime + Parameters.DELAY_DURATION);
        assertEq(_xanProxy.delayedUpgradeImplementation(), _IMPL);
    }

    function test_startUpgradeDelay_emits_the_DelayStarted_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.totalSupply());
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        uint48 currentTime = Time.timestamp();
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.DelayStarted({
            implementation: _IMPL,
            startTime: currentTime,
            endTime: currentTime + Parameters.DELAY_DURATION
        });
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_if_the_minimal_locked_supply_is_not_met() public {
        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY - 1);

        vm.expectRevert(abi.encodeWithSelector(XanV1.MinLockedSupplyNotReached.selector), address(_xanProxy));
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_if_quorum_is_not_met() public {
        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        vm.startPrank(_defaultSender);
        // Lock first half.
        _xanProxy.lock(quorumThreshold);
        // Vote with first half.
        _xanProxy.castVote(_IMPL);

        // Lock second half.
        _xanProxy.lock(quorumThreshold);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _IMPL), address(_xanProxy));
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_if_delay_has_already_been_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        // Start the delay
        _xanProxy.startUpgradeDelay(_IMPL);

        // Try to start the delay again.
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodAlreadyStarted.selector, _IMPL), address(_xanProxy));
        _xanProxy.startUpgradeDelay(_IMPL);
    }

    function test_startUpgradeDelay_reverts_is_not_ranked_best() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _OTHER_IMPL);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _IMPL, _OTHER_IMPL), address(_xanProxy)
        );
        _xanProxy.startUpgradeDelay(_OTHER_IMPL);
    }

    function test_resetUpgradeDelay_reverts_on_winning_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);

        // Skip the delay period.
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(abi.encodeWithSelector(XanV1.UpgradeDelayNotResettable.selector, _IMPL), address(_xanProxy));
        _xanProxy.resetUpgradeDelay(_IMPL);
    }

    function test_resetUpgradeDelay_emits_the_DelayReset_event() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        _xanProxy.startUpgradeDelay(_IMPL);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Reset the delay
        vm.expectEmit(address(_xanProxy));
        emit IXanV1.DelayReset({implementation: _IMPL});
        _xanProxy.resetUpgradeDelay(_IMPL);
    }

    function test_resetUpgradeDelay_resets_the_delay() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        _xanProxy.startUpgradeDelay(_IMPL);

        uint48 currentTime = Time.timestamp();

        assertEq(_xanProxy.delayEndTime(), currentTime + Parameters.DELAY_DURATION);
        assertEq(_xanProxy.delayedUpgradeImplementation(), _IMPL);

        // Vote with more weight for another implementation
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL);

        // Advance to the end of the delay period.
        skip(Parameters.DELAY_DURATION);

        // Reset the delay
        _xanProxy.resetUpgradeDelay(_IMPL);

        // Check state change has happened
        assertEq(_xanProxy.delayEndTime(), 0);
        assertEq(_xanProxy.delayedUpgradeImplementation(), address(0));
    }

    function test_upgradeToAndCall_reverts_if_implementation_has_not_been_voted_on() public {
        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_the_delay_period_has_passed_for_a_different_implementation() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_OTHER_IMPL);
        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotDelayed.selector, _OTHER_IMPL, _IMPL), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_delay_period_has_not_started() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(_xanProxy.calculateQuorumThreshold() + 1);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotStarted.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_delay_period_has_not_ended() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.DelayPeriodNotEnded.selector), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_quorum_is_not_met() public {
        vm.startPrank(_defaultSender);
        _xanProxy.lock(Parameters.MIN_LOCKED_SUPPLY);
        _xanProxy.castVote(_IMPL);
        vm.stopPrank();

        _xanProxy.startUpgradeDelay(_IMPL);
        skip(Parameters.DELAY_DURATION);

        vm.prank(_defaultSender);
        _xanProxy.revokeVote(_IMPL);

        vm.expectRevert(abi.encodeWithSelector(XanV1.QuorumNotReached.selector, _IMPL), address(_xanProxy));
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
    }

    function test_upgradeToAndCall_reverts_if_implementation_is_not_best_ranked() public {
        vm.startPrank(_defaultSender);

        uint256 quorumThreshold =
            (_xanProxy.totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;

        // Meet the quorum threshold with one excess vote.
        _xanProxy.lock(quorumThreshold + 1);
        _xanProxy.castVote(_IMPL);
        assertEq(_xanProxy.proposedImplementationByRank(0), _IMPL);

        _xanProxy.startUpgradeDelay(_IMPL);
        _xanProxy.lock(1);
        _xanProxy.castVote(_OTHER_IMPL);
        vm.stopPrank();

        assertEq(_xanProxy.proposedImplementationByRank(0), _OTHER_IMPL); // Delay has not started
        assertEq(_xanProxy.proposedImplementationByRank(1), _IMPL); // Delay has started

        skip(Parameters.DELAY_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(XanV1.ImplementationNotRankedBest.selector, _OTHER_IMPL, _IMPL), address(_xanProxy)
        );
        _xanProxy.upgradeToAndCall({newImplementation: _IMPL, data: ""});
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

    function test_permits_spending_given_an_EIP712_signature() public {
        uint256 alicePrivKey = 0xA11CE;
        address aliceAddr = vm.addr(alicePrivKey);
        address spender = address(uint160(4));

        // Give funds to Alice
        vm.prank(_defaultSender);
        _xanProxy.transfer({to: aliceAddr, value: 1_000});

        // Sign message
        uint256 nonce = _xanProxy.nonces(aliceAddr);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 500;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                aliceAddr,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = _xanProxy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivKey, digest);

        // Check that the spender is allowed to spend 0 XAN of Alice before the `permit` call.
        assertEq(_xanProxy.allowance({owner: aliceAddr, spender: spender}), 0);

        // Given the signature, anyone (here `_defaultSender`) can set the allowance.
        vm.prank(_defaultSender);
        _xanProxy.permit({owner: aliceAddr, spender: spender, value: value, deadline: deadline, v: v, r: r, s: s});

        // Check that the spender is allowed to spend `value` XAN of Alice after the `permit` call.
        assertEq(_xanProxy.allowance({owner: aliceAddr, spender: spender}), value);
    }

    function test_initialize_mints_the_expected_supply_amounting_to_1_billion_tokens() public view {
        uint256 expectedTokens = 10 ** 9;

        // Consider the decimals for the expected supply.
        uint256 expectedSupply = expectedTokens * (10 ** _xanProxy.decimals());

        assertEq(Parameters.SUPPLY, expectedSupply);
        assertEq(_xanProxy.totalSupply(), expectedSupply);
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
