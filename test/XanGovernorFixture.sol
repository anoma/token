// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {XanGovernor} from "../src/XanGovernor.sol";
import {XanV1} from "../src/XanV1.sol";
import {XanV2} from "../src/XanV2.sol";
import {MockXanV2} from "./mocks/MockXanV2.sol";

/// @notice Shared fixture wiring a `XanGovernor` DAO to the `XanV2` token through a `TimelockController`.
/// @dev The end state mirrors a real deployment: the token's whole supply is held and self-delegated by
/// `_voter`, the token is owned by the timelock, and the governor is the timelock's sole proposer/canceller while
/// anyone may execute. This makes the governor the only path to privileged token actions such as upgrades.
abstract contract XanGovernorFixture is Test {
    /// @notice Voting delay in seconds (the token clock is timestamp-based).
    uint48 internal constant _VOTING_DELAY = 1;
    /// @notice Voting period in seconds.
    uint32 internal constant _VOTING_PERIOD = 50;
    /// @notice No voting power is required to create a proposal in this example.
    uint256 internal constant _PROPOSAL_THRESHOLD = 0;
    /// @notice Quorum as a percentage of the voting supply, reusing the V1 quorum ratio (50%). `GovernorVotesQuorumFraction`
    /// uses a denominator of 100, so the V1 ratio is rescaled from its denominator of `QUORUM_RATIO_DENOMINATOR`.
    uint256 internal constant _QUORUM_NUMERATOR =
        Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR;
    /// @notice The minimum delay enforced by the timelock between queueing and execution, reusing the V1 upgrade delay.
    uint256 internal constant _TIMELOCK_MIN_DELAY = Parameters.DELAY_DURATION;

    address internal immutable _COUNCIL = makeAddr("council");
    address internal immutable _OTHER = makeAddr("other");

    XanV2 internal _xanToken;
    XanGovernor internal _governor;
    TimelockController internal _timelock;
    address internal _v1Implementation;

    /// @notice The account that received the initial mint and holds the entire voting supply.
    address internal _voter;
    /// @notice An unprivileged account used for negative checks.
    address internal _other;

    function setUp() public virtual {
        (, _voter,) = vm.readCallers();

        // Deploy the V1 proxy (mints the whole supply to `_voter`) and win a voter-body upgrade vote for a V2
        // implementation, reusing the same locking/voting flow the production upgrade follows.
        XanV1 xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1", initializerData: abi.encodeCall(XanV1.initializeV1, (_voter, _COUNCIL))
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
            new MockXanV2(_v1Implementation, address(_timelock), Parameters.VESTING_START, Parameters.VESTING_DURATION)
        );

        vm.startPrank(_voter);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_voter));
        xanV1Proxy.castVote(xanV2Impl);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();
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
            initialVotingDelay: _VOTING_DELAY,
            initialVotingPeriod: _VOTING_PERIOD,
            initialProposalThreshold: _PROPOSAL_THRESHOLD,
            quorumNumerator: _QUORUM_NUMERATOR
        });

        // The governor proposes and cancels; anyone may execute once the timelock delay elapses.
        _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_governor));
        _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_governor));
        _timelock.grantRole(_timelock.EXECUTOR_ROLE(), address(0));
        _timelock.renounceRole(_timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Activate voting power: the token tracks votes only once an account delegates (here, to itself).
        vm.prank(_voter);
        _xanToken.delegate(_voter);

        // Move past the delegation checkpoint so the voting snapshot taken at proposal time can read it.
        vm.warp(block.timestamp + 1);
    }

    /// @notice Runs a proposal through its full lifecycle: propose, vote `For`, queue, and execute.
    /// @dev Mirrors the canonical OpenZeppelin governor flow and is shared by the voting and upgrade demos.
    function _passProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256 proposalId) {
        vm.prank(_voter);
        proposalId = _governor.propose(targets, values, calldatas, description);

        // Voting opens after `votingDelay` seconds.
        vm.warp(block.timestamp + _governor.votingDelay() + 1);
        vm.prank(_voter);
        _governor.castVote(proposalId, uint8(1)); // 1 == For

        // Voting closes after `votingPeriod` seconds.
        vm.warp(block.timestamp + _governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        _governor.queue(targets, values, calldatas, descriptionHash);

        // Wait out the timelock delay, then execute.
        skip(_TIMELOCK_MIN_DELAY + 1);
        _governor.execute(targets, values, calldatas, descriptionHash);
    }
}
