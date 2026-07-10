// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {DeployGovernance} from "../../script/DeployGovernance.s.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanGovernor} from "../../src/XanGovernor.sol";
import {XanUpgradeCouncil} from "../../src/XanUpgradeCouncil.sol";
import {XanV1} from "../../src/XanV1.sol";

/// @notice Pins the production governance wiring produced by `DeployGovernance`. The deploy script establishes the
/// entire security posture of the layer — who may schedule and cancel, that execution is permissionless, and that no
/// residual deployer privilege survives — so every role assignment is asserted here explicitly.
contract DeployGovernanceTest is Test {
    address internal immutable _COUNCIL_MULTISIG = makeAddr("councilMultisig");
    address internal immutable _ATTACKER = makeAddr("attacker");

    DeployGovernance internal _script;
    address internal _deployer;
    address internal _token;
    XanGovernor internal _governor;
    TimelockController internal _timelock;
    XanUpgradeCouncil internal _upgradeCouncil;

    function setUp() public {
        _token = Upgrades.deployUUPSProxy(
            "XanV1.sol:XanV1", abi.encodeCall(XanV1.initializeV1, (makeAddr("mintRecipient"), makeAddr("v1Council")))
        );

        _script = new DeployGovernance();
        _deployer = address(_script);
        (address governor, address timelock, address upgradeCouncil) =
            _script.deploy({token: _token, councilMultisig: _COUNCIL_MULTISIG, deployer: _deployer});

        _governor = XanGovernor(payable(governor));
        _timelock = TimelockController(payable(timelock));
        _upgradeCouncil = XanUpgradeCouncil(upgradeCouncil);
    }

    function test_deploy_reverts_if_the_token_is_the_zero_address() public {
        vm.expectRevert(DeployGovernance.InvalidTokenAddress.selector, address(_script));
        _script.deploy({token: address(0), councilMultisig: _COUNCIL_MULTISIG, deployer: address(_script)});
    }

    function test_deploy_reverts_if_the_council_is_the_zero_address() public {
        vm.expectRevert(DeployGovernance.InvalidCouncilAddress.selector, address(_script));
        _script.deploy({token: _token, councilMultisig: address(0), deployer: address(_script)});
    }

    /// @notice The timelock self-administers: role changes require a passed governance operation, so an outsider
    /// cannot grant itself scheduling or cancelling power.
    function test_roles_cannot_be_changed_by_outsiders() public {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 adminRole = _timelock.DEFAULT_ADMIN_ROLE();

        vm.prank(_ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _ATTACKER, adminRole),
            address(_timelock)
        );
        _timelock.grantRole(proposerRole, _ATTACKER);
    }

    /// @notice Exactly the governor and the council module may schedule and cancel timelock operations.
    function test_run_grants_scheduling_and_cancelling_to_the_governor_and_the_module() public view {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = _timelock.CANCELLER_ROLE();

        assertTrue(_timelock.hasRole(proposerRole, address(_governor)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_governor)));
        assertTrue(_timelock.hasRole(proposerRole, address(_upgradeCouncil)));
        assertTrue(_timelock.hasRole(cancellerRole, address(_upgradeCouncil)));

        // Neither the council multisig nor the token hold timelock roles directly — all council power flows through
        // the module's narrow interface.
        assertFalse(_timelock.hasRole(proposerRole, _COUNCIL_MULTISIG));
        assertFalse(_timelock.hasRole(cancellerRole, _COUNCIL_MULTISIG));
        assertFalse(_timelock.hasRole(proposerRole, _token));
    }

    /// @notice Anyone may execute a ready operation: authority lives entirely in scheduling and cancelling.
    function test_run_opens_the_executor_role() public view {
        assertTrue(_timelock.hasRole(_timelock.EXECUTOR_ROLE(), address(0)));
    }

    /// @notice After deployment only the timelock administers its own roles; the deployer's temporary admin is gone.
    function test_run_leaves_the_timelock_self_administered() public view {
        bytes32 adminRole = _timelock.DEFAULT_ADMIN_ROLE();

        assertTrue(_timelock.hasRole(adminRole, address(_timelock)));

        // No deployer-side account retains admin: not the deployer, not the test contract, and none of the wired
        // contracts.
        assertFalse(_timelock.hasRole(adminRole, _deployer));
        assertFalse(_timelock.hasRole(adminRole, address(this)));
        assertFalse(_timelock.hasRole(adminRole, address(_governor)));
        assertFalse(_timelock.hasRole(adminRole, address(_upgradeCouncil)));
    }

    function test_run_sets_the_timelock_min_delay() public view {
        assertEq(_timelock.getMinDelay(), Parameters.DELAY_DURATION);
    }

    /// @notice The governor reads votes from the token, executes through the timelock, and carries the `Parameters`
    /// settings — including the 50% quorum the council's capture-cost argument depends on (ADR-0007).
    function test_run_configures_the_governor() public view {
        assertEq(address(_governor.token()), _token);
        assertEq(_governor.timelock(), address(_timelock));
        assertEq(_governor.votingDelay(), Parameters.VOTING_DELAY);
        assertEq(_governor.votingPeriod(), Parameters.VOTING_PERIOD);
        assertEq(_governor.proposalThreshold(), Parameters.PROPOSAL_THRESHOLD);
        assertEq(
            _governor.quorumNumerator(), Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR
        );
    }

    /// @notice The quorum-numerator checkpoint is keyed by the deploy timestamp, so the numerator holds from then
    /// on with no earlier (block-number-keyed) checkpoint.
    function test_quorum_numerator_is_checkpointed_at_the_deploy_timestamp() public view {
        uint48 deployTimestamp = Time.timestamp();
        uint256 expectedNumerator = Parameters.QUORUM_RATIO_NUMERATOR * 100 / Parameters.QUORUM_RATIO_DENOMINATOR;

        assertEq(_governor.quorumNumerator(deployTimestamp), expectedNumerator, "numerator not set at deploy timestamp");
        assertEq(_governor.quorumNumerator(deployTimestamp - 1), 0, "checkpoint exists before the deploy timestamp");
    }

    /// @notice The timelock owns the module (and thus rotates the council); the multisig is the initial council.
    function test_run_wires_the_module() public view {
        assertEq(_upgradeCouncil.owner(), address(_timelock));
        assertEq(_upgradeCouncil.council(), _COUNCIL_MULTISIG);
        assertEq(
            _upgradeCouncil.cancelWindow(),
            uint256(Parameters.VOTING_DELAY) + Parameters.VOTING_PERIOD + Parameters.DELAY_DURATION
                + Parameters.COUNCIL_CANCEL_BUFFER
        );
    }
}
