// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../../src/libs/Parameters.sol";
import {XanGovernor} from "../../src/XanGovernor.sol";
import {XanV1} from "../../src/XanV1.sol";
import {XanV2} from "../../src/XanV2.sol";
import {MockXanV2} from "../mocks/MockXanV2.sol";

/// @notice Shared fixture wiring a `XanGovernor` DAO to the `XanV2` token through a `TimelockController`.
/// @dev Five self-delegating voters: A 40%, B and C 25%, D and E 5%. Against the 10% quorum, D or E alone falls
/// short and the two together meet it exactly; A, D, and E balance B and C for a tie.
abstract contract XanGovernorFixture is Test {
    uint256 internal constant _PROPOSAL_THRESHOLD = Parameters.GOVERNOR_PROPOSAL_THRESHOLD;
    uint256 internal constant _QUORUM_NUMERATOR = Parameters.GOVERNOR_QUORUM_NUMERATOR;
    uint256 internal constant _TIMELOCK_MIN_DELAY = Parameters.TIMELOCK_MIN_DELAY;

    uint256 internal constant _5_PERCENT = Parameters.SUPPLY * 5 / 100;
    uint256 internal constant _25_PERCENT = Parameters.SUPPLY * 25 / 100;
    uint256 internal constant _40_PERCENT = Parameters.SUPPLY * 40 / 100;

    address internal immutable _COUNCIL = makeAddr("council");
    address internal immutable _OTHER = makeAddr("other");

    XanV2 internal _xanToken;
    XanGovernor internal _governor;
    TimelockController internal _timelock;
    address internal _v1Implementation;

    /// @dev A receives the initial mint and keeps the remainder after `setUp` splits the supply.
    address internal _voterA;
    address internal _voterB;
    address internal _voterC;
    address internal _voterD;
    address internal _voterE;

    function setUp() public virtual {
        (, _voterA,) = vm.readCallers();

        // Deploy the V1 proxy (mints the whole supply to `_voterA`) and win a voter-body upgrade vote for a V2
        // implementation, reusing the same locking/voting flow the production upgrade follows.
        XanV1 xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_voterA, _COUNCIL))
            })
        );
        _v1Implementation = xanV1Proxy.implementation();

        // Deploy the timelock first, with no preset roles, so it can be baked into the V2 implementation as the
        // (immutable) token owner; roles are wired up after the governor exists.
        address[] memory empty = new address[](0);
        _timelock = new TimelockController({
            minDelay: _TIMELOCK_MIN_DELAY, proposers: empty, executors: empty, admin: address(this)
        });

        // The owner (the timelock) and vesting schedule are bound into the implementation bytecode at deployment.
        address xanV2Impl = address(
            new MockXanV2(
                _v1Implementation, address(_timelock), Parameters.XAN_VESTING_START, Parameters.XAN_VESTING_DURATION
            )
        );

        // Seed the electorate as locked V1 principals via `transferAndLock` (mint-recipient-only), so everyone votes
        // with vesting tokens. The three large stakes clear V1's upgrade quorum; then A schedules the upgrade.
        _voterB = makeAddr("voterB");
        _voterC = makeAddr("voterC");
        _voterD = makeAddr("voterD");
        _voterE = makeAddr("voterE");
        vm.startPrank(_voterA);
        xanV1Proxy.transferAndLock(_voterB, _25_PERCENT);
        xanV1Proxy.transferAndLock(_voterC, _25_PERCENT);
        xanV1Proxy.transferAndLock(_voterD, _5_PERCENT);
        xanV1Proxy.transferAndLock(_voterE, _5_PERCENT);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_voterA));
        xanV1Proxy.castVote(xanV2Impl);
        vm.stopPrank();
        vm.prank(_voterB);
        xanV1Proxy.castVote(xanV2Impl);
        vm.prank(_voterC);
        xanV1Proxy.castVote(xanV2Impl);
        vm.prank(_voterA);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        skip(Parameters.DELAY_DURATION);

        // Upgrade the proxy to V2; ownership (the timelock) is already baked into the implementation, so only the
        // DAO can authorize token upgrades.
        UnsafeUpgrades.upgradeProxy({
            proxy: address(xanV1Proxy), newImpl: xanV2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });
        _xanToken = XanV2(address(xanV1Proxy));

        _governor = new XanGovernor({
            xanToken: IVotes(address(_xanToken)),
            timelockController: _timelock,
            initialVotingDelay: _votingDelay(),
            initialVotingPeriod: _votingPeriod(),
            initialProposalThreshold: _PROPOSAL_THRESHOLD,
            initialQuorumNumerator: _QUORUM_NUMERATOR
        });

        // The governor proposes and cancels; anyone may execute once the timelock delay elapses.
        _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_governor));
        _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_governor));
        _timelock.grantRole(_timelock.EXECUTOR_ROLE(), address(0));
        _timelock.renounceRole(_timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Activate voting power: the token tracks votes only once an account delegates (here, each to itself).
        vm.prank(_voterA);
        _xanToken.delegate(_voterA);
        vm.prank(_voterB);
        _xanToken.delegate(_voterB);
        vm.prank(_voterC);
        _xanToken.delegate(_voterC);
        vm.prank(_voterD);
        _xanToken.delegate(_voterD);
        vm.prank(_voterE);
        _xanToken.delegate(_voterE);

        // Move past the delegation checkpoints so the voting snapshot taken at proposal time can read them.
        vm.warp(Time.timestamp() + 1 seconds);
    }

    /// @notice Runs a proposal through its full lifecycle: propose, vote `For`, queue, and execute.
    /// @dev Mirrors the canonical OpenZeppelin governor flow and is shared by the voting and upgrade demos.
    function _passProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        vm.prank(_voterA);
        proposalId = _governor.propose(targets, values, calldatas, description);

        _warpIntoVotingPeriod();
        vm.prank(_voterA);
        _governor.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        _warpPastVotingPeriod();

        bytes32 descriptionHash = keccak256(bytes(description));
        _governor.queue(targets, values, calldatas, descriptionHash);

        // Wait out the (live) timelock delay, then execute.
        skip(_timelock.getMinDelay() + 1);
        _governor.execute(targets, values, calldatas, descriptionHash);
    }

    /// @notice Has the voter body propose, pass, and queue (but not execute) an arbitrary proposal.
    /// @return descriptionHash The hash of the proposal description, needed to rebuild its timelock operation id.
    function _queueVoterBodyProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (bytes32 descriptionHash) {
        descriptionHash = keccak256(bytes(description));

        vm.prank(_voterA);
        uint256 proposalId =
            _governor.propose({targets: targets, values: values, calldatas: calldatas, description: description});

        _warpIntoVotingPeriod();
        vm.prank(_voterA);
        _governor.castVote(proposalId, uint8(1));

        _warpPastVotingPeriod();
        _governor.queue({targets: targets, values: values, calldatas: calldatas, descriptionHash: descriptionHash});
    }

    /// @notice Warps to just inside the voting period (one second past the voting delay), so the proposal is `Active`
    /// and votes can be cast.
    function _warpIntoVotingPeriod() internal {
        vm.warp(Time.timestamp() + _governor.votingDelay() + 1 seconds);
    }

    /// @notice Warps to just past the voting period, so voting has closed and a passing proposal can be queued.
    function _warpPastVotingPeriod() internal {
        vm.warp(Time.timestamp() + _governor.votingPeriod() + 1 seconds);
    }

    /// @notice The governor's initial voting delay (the token clock is timestamp-based). Compressed by default to
    /// keep proposals cheap; a suite whose behaviour depends on the real timings overrides it.
    function _votingDelay() internal view virtual returns (uint48 votingDelay) {
        votingDelay = 1 seconds;
    }

    /// @notice The governor's initial voting period. Compressed by default, see `_votingDelay`.
    function _votingPeriod() internal view virtual returns (uint32 votingPeriod) {
        votingPeriod = 50 seconds;
    }
}
