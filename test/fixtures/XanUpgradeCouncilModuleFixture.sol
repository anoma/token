// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IXanUpgradeCouncilModule} from "../../src/interfaces/IXanUpgradeCouncilModule.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {XanUpgradeCouncilModule} from "../../src/XanUpgradeCouncilModule.sol";
import {MockXanV2} from "../mocks/MockXanV2.sol";
import {XanGovernorFixture} from "./XanGovernorFixture.sol";

/// @notice Extends the governor fixture with a wired `XanUpgradeCouncilModule`: the module is granted the timelock's
/// `PROPOSER` and `CANCELLER` roles, so the council can schedule token upgrades (and withdraw its own pending one) and
/// the voter body can cancel the council. Mirrors a real deployment where the token is owned by the timelock.
abstract contract XanUpgradeCouncilModuleFixture is XanGovernorFixture {
    /// @notice The upgrade council multisig.
    address internal immutable _COUNCIL_MULTISIG = makeAddr("upgradeCouncilMultisig");

    XanUpgradeCouncilModule internal _module;

    function setUp() public virtual override {
        super.setUp();

        _module = new XanUpgradeCouncilModule({
            governor: IGovernor(address(_governor)),
            timelock: _timelock,
            council: _COUNCIL_MULTISIG,
            token: address(_xanToken),
            extraDelay: Parameters.COUNCIL_EXTRA_DELAY
        });

        // The base fixture renounced the deployer's timelock admin, so roles are now changed only through the timelock
        // itself; impersonating it here stands in for the governance proposal that would grant these roles in prod.
        vm.startPrank(address(_timelock));
        _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_module));
        _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_module));
        vm.stopPrank();
    }

    /// @notice Deploys a fresh implementation to upgrade the token to.
    function _newImplementation() internal returns (address newImpl) {
        newImpl = address(
            new MockXanV2({
                v1Implementation: _v1Implementation,
                owner: address(_timelock),
                vestingStart: Parameters.XAN_VESTING_START,
                vestingDuration: Parameters.XAN_VESTING_DURATION
            })
        );
    }

    /// @notice Schedules a council upgrade, returning the operation id and the schedule timestamp callers need to
    /// rebuild the operation.
    /// @dev Reads through `vm.getBlockTimestamp()`: callers hold the value across a `warp`, and solc may fold a
    /// plain timestamp local into a fresh read that the warp then invalidates.
    function _scheduleCouncilUpgrade(address newImpl, bytes memory data)
        internal
        returns (bytes32 operationId, uint48 scheduledAt)
    {
        scheduledAt = uint48(vm.getBlockTimestamp());
        vm.prank(_COUNCIL_MULTISIG);
        operationId = _module.scheduleUpgrade(newImpl, data);
    }

    /// @notice Executes a scheduled council upgrade through the (open-executor) timelock.
    function _executeCouncilUpgrade(address newImpl, bytes memory data, uint48 scheduledAt) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads, bytes32 salt) =
            _councilUpgradeBatch(newImpl, data, scheduledAt);
        _timelock.executeBatch({
            targets: targets, values: values, payloads: payloads, predecessor: bytes32(0), salt: salt
        });
    }

    /// @notice Cancels a council upgrade the way the voter body does it: a passed proposal relaying
    /// `timelock.cancel(operationId)` through the governor (which holds `CANCELLER`).
    function _cancelCouncilUpgradeThroughGovernor(bytes32 operationId) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _cancelCouncilUpgradeCall(operationId);

        _passProposal({
            targets: targets, values: values, calldatas: calldatas, description: "cancel the council upgrade"
        });
    }

    /// @notice Expects the next call to revert because the timelock operation is not `Ready` — still waiting,
    /// already executed, or cancelled.
    function _expectTimelockOperationNotReady(bytes32 operationId) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                operationId,
                _timelockStateBitmap(TimelockController.OperationState.Ready)
            ),
            address(_timelock)
        );
    }

    /// @notice Builds the voter-body proposal payload cancelling a council upgrade.
    function _cancelCouncilUpgradeCall(bytes32 operationId)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(_governor);
        bytes memory cancelCall = abi.encodeCall(TimelockController.cancel, (operationId));
        calldatas[0] = abi.encodeCall(Governor.relay, (address(_timelock), uint256(0), cancelCall));
    }

    /// @notice Rebuilds the council's two-call upgrade batch and salt (deterministic, matching the module):
    /// `checkUpgradeDelayElapsed`, then the token upgrade.
    function _councilUpgradeBatch(address newImpl, bytes memory data, uint48 scheduledAt)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads, bytes32 salt)
    {
        targets = new address[](2);
        values = new uint256[](2);
        payloads = new bytes[](2);

        targets[0] = address(_module);
        payloads[0] = abi.encodeCall(IXanUpgradeCouncilModule.checkUpgradeDelayElapsed, (scheduledAt));

        targets[1] = address(_xanToken);
        payloads[1] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, data));

        salt = keccak256(abi.encode("XanUpgradeCouncilModule.upgrade", newImpl, data));
    }

    /// @notice Computes the timelock operation id of a council upgrade.
    function _councilOperationId(address newImpl, bytes memory data, uint48 scheduledAt)
        internal
        view
        returns (bytes32 operationId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads, bytes32 salt) =
            _councilUpgradeBatch(newImpl, data, scheduledAt);
        operationId = _timelock.hashOperationBatch({
            targets: targets, values: values, payloads: payloads, predecessor: bytes32(0), salt: salt
        });
    }

    /// @notice The single-state bitmap `TimelockController` uses to describe an operation's expected state in its
    /// `TimelockUnexpectedOperationState` error (mirrors OZ's internal `_encodeStateBitmap`).
    function _timelockStateBitmap(TimelockController.OperationState state) private pure returns (bytes32 bitmap) {
        bitmap = bytes32(uint256(1) << uint8(state));
    }
}
