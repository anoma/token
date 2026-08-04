// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanUpgradeCouncilModule} from "./interfaces/IXanUpgradeCouncilModule.sol";

/// @title XanUpgradeCouncilModule
/// @author Anoma Foundation, 2026
/// @notice The upgrade council's on-chain interface to XAN governance. The module holds the timelock's `PROPOSER` and
/// `CANCELLER` roles and lets the council:
/// * Schedule a XAN token upgrade that the voter body can cancel.
/// * Withdraw its own pending upgrade.
/// It holds no power over voter-body operations.
/// @custom:security-contact security@anoma.foundation
contract XanUpgradeCouncilModule is IXanUpgradeCouncilModule {
    /// @notice The governor whose voting parameters size the upgrade delay.
    IGovernor private immutable _GOVERNOR;

    /// @notice The timelock that owns the token and through which upgrades are scheduled, cancelled, and executed.
    TimelockController private immutable _TIMELOCK;

    /// @notice The council multisig that can schedule and cancel upgrade proposals.
    address private immutable _COUNCIL;

    /// @notice The XAN token proxy that upgrades target.
    address private immutable _TOKEN;

    /// @notice Margin added on top of the voter cancel cycle, giving the voter body time to notice a scheduled
    /// upgrade before its cancel cycle must start.
    uint256 private immutable _EXTRA_DELAY;

    /// @notice The most recently scheduled council upgrade operation id.
    bytes32 private _lastScheduledUpgradeOperationId;

    /// @notice Thrown when a council-only function is called by another account.
    error UnauthorizedCouncil(address caller);

    /// @notice Thrown when the council schedules an upgrade while one is already pending (one upgrade in flight).
    error UpgradeAlreadyPending(bytes32 operationId);

    /// @notice Thrown when the governor address supplied to the constructor is zero.
    error ZeroGovernorNotAllowed();

    /// @notice Thrown when the timelock address supplied to the constructor is zero.
    error ZeroTimelockNotAllowed();

    /// @notice Thrown when the council address supplied to the constructor is zero.
    error ZeroCouncilNotAllowed();

    /// @notice Thrown when the token address supplied to the constructor is zero.
    error ZeroTokenNotAllowed();

    /// @notice Thrown when the extra delay supplied to the constructor is zero, which would collapse the upgrade
    /// delay down to the bare voter cancel cycle and leave the voter body no time to react.
    error ZeroExtraDelayNotAllowed();

    /// @notice Thrown when the implementation address supplied to `scheduleUpgrade` is zero.
    error ZeroImplementationNotAllowed();

    /// @notice Thrown when `cancelUpgrade` is called but no council upgrade is pending in the timelock.
    error NoUpgradePending();

    /// @notice Thrown by `checkUpgradeDelayElapsed` when the upgrade delay, recomputed from the current settings, has
    /// not yet elapsed since the upgrade was scheduled.
    error UpgradeDelayNotElapsed(uint48 scheduledAt, uint256 executableAt);

    /// @notice Restricts a function to the council multisig.
    modifier onlyCouncil() {
        _checkCouncil();
        _;
    }

    /// @notice Deploys the module. It must be granted the timelock's `PROPOSER` and `CANCELLER` roles after deployment.
    /// @param governor The governor whose `votingDelay`/`votingPeriod` size the upgrade delay.
    /// @param timelock The timelock that owns the token and through which upgrades are scheduled and cancelled.
    /// @param council The council multisig.
    /// @param token The XAN token proxy.
    /// @param extraDelay The margin added on top of the voter cancel cycle.
    constructor(IGovernor governor, TimelockController timelock, address council, address token, uint256 extraDelay) {
        require(address(governor) != address(0), ZeroGovernorNotAllowed());
        require(address(timelock) != address(0), ZeroTimelockNotAllowed());
        require(council != address(0), ZeroCouncilNotAllowed());
        require(token != address(0), ZeroTokenNotAllowed());
        require(extraDelay != 0, ZeroExtraDelayNotAllowed());

        _GOVERNOR = governor;
        _TIMELOCK = timelock;
        _COUNCIL = council;
        _TOKEN = token;
        _EXTRA_DELAY = extraDelay;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Callable only by the council. The delay is sized (see `upgradeDelay`) to leave a full voter cancel cycle.
    /// Only one council upgrade may be pending at a time.
    function scheduleUpgrade(address newImplementation, bytes calldata data)
        external
        override
        onlyCouncil
        returns (bytes32 operationId)
    {
        require(newImplementation != address(0), ZeroImplementationNotAllowed());
        // One council upgrade in flight at a time.
        require(
            _lastScheduledUpgradeOperationId == bytes32(0)
                || !_TIMELOCK.isOperationPending(_lastScheduledUpgradeOperationId),
            UpgradeAlreadyPending(_lastScheduledUpgradeOperationId)
        );

        uint256 delay = upgradeDelay();
        bytes32 salt = _salt(newImplementation, data);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads, uint48 scheduledAt) =
            _upgradeBatch(newImplementation, data);

        operationId = _TIMELOCK.hashOperationBatch({
            targets: targets, values: values, payloads: payloads, predecessor: bytes32(0), salt: salt
        });
        _lastScheduledUpgradeOperationId = operationId;

        emit UpgradeScheduled({
            newImplementation: newImplementation,
            data: data,
            operationId: operationId,
            scheduledAt: scheduledAt,
            earliestExecutableAt: scheduledAt + delay
        });

        _TIMELOCK.scheduleBatch({
            targets: targets, values: values, payloads: payloads, predecessor: bytes32(0), salt: salt, delay: delay
        });
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Callable only by the council. The module only ever aims the timelock's `CANCELLER` role at the operation
    /// it scheduled itself, so the council has no cancel power over voter-body operations.
    function cancelUpgrade() external override onlyCouncil returns (bytes32 operationId) {
        operationId = _lastScheduledUpgradeOperationId;
        require(operationId != bytes32(0) && _TIMELOCK.isOperationPending(operationId), NoUpgradePending());

        emit UpgradeCancelled(operationId);

        _TIMELOCK.cancel(operationId);
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Runs as the first call of every council upgrade batch, so the timelock re-checks it on each execution
    /// attempt. The timelock freezes its deadline at scheduling while a cancel cycle is computed live, so a later
    /// settings raise would otherwise let the upgrade outrun any cancellation.
    function checkUpgradeDelayElapsed(uint48 scheduledAt) external view override {
        uint256 executableAt = scheduledAt + upgradeDelay();
        require(
            Time.timestamp() + 1 > executableAt,
            UpgradeDelayNotElapsed({scheduledAt: scheduledAt, executableAt: executableAt})
        );
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getCouncil() external view override returns (address council) {
        council = _COUNCIL;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getTimelock() external view override returns (address timelock) {
        timelock = address(_TIMELOCK);
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getGovernor() external view override returns (address governor) {
        governor = address(_GOVERNOR);
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getToken() external view override returns (address token) {
        token = _TOKEN;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getExtraDelay() external view override returns (uint256 extraDelay) {
        extraDelay = _EXTRA_DELAY;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    function getLastScheduledUpgradeOperationId() external view override returns (bytes32 operationId) {
        operationId = _lastScheduledUpgradeOperationId;
    }

    /// @inheritdoc IXanUpgradeCouncilModule
    /// @dev Computed live as `votingDelay + votingPeriod + timelock.getMinDelay() + extraDelay`, so it always
    /// exceeds a full voter cancel cycle.
    function upgradeDelay() public view override returns (uint256 delay) {
        delay = _GOVERNOR.votingDelay() + _GOVERNOR.votingPeriod() + _TIMELOCK.getMinDelay() + _EXTRA_DELAY;
    }

    /// @notice Checks that the caller is the council.
    function _checkCouncil() internal view {
        require(_COUNCIL == msg.sender, UnauthorizedCouncil({caller: msg.sender}));
    }

    /// @notice Builds the council upgrade batch: `checkUpgradeDelayElapsed` first, then the token upgrade.
    /// `executeBatch` runs them in order and reverts the whole execution if `checkUpgradeDelayElapsed` does.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @return targets The batch call targets.
    /// @return values The batch call values (all zero).
    /// @return payloads The batch call payloads.
    /// @return scheduledAt The current timestamp, which `checkUpgradeDelayElapsed` measures its delay from.
    function _upgradeBatch(address newImplementation, bytes calldata data)
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads, uint48 scheduledAt)
    {
        targets = new address[](2);
        values = new uint256[](2);
        payloads = new bytes[](2);

        scheduledAt = Time.timestamp();

        targets[0] = address(this);
        payloads[0] = abi.encodeCall(IXanUpgradeCouncilModule.checkUpgradeDelayElapsed, (scheduledAt));

        targets[1] = _TOKEN;
        payloads[1] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImplementation, data));
    }

    /// @notice Deterministic, council-tagged salt so a council upgrade never collides with a voter-body operation.
    /// @param newImplementation The implementation to upgrade the token to.
    /// @param data The reinitialization calldata forwarded to `upgradeToAndCall`.
    /// @return salt The operation salt.
    function _salt(address newImplementation, bytes calldata data) private pure returns (bytes32 salt) {
        salt = keccak256(abi.encode("XanUpgradeCouncilModule.upgrade", newImplementation, data));
    }
}
