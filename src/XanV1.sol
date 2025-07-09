// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanV1} from "./interfaces/IXanV1.sol";
import {Council} from "./libs/Council.sol";
import {Locking} from "./libs/Locking.sol";
import {Parameters} from "./libs/Parameters.sol";
import {Voting} from "./libs/Voting.sol";

/// @title XanV1
/// @author Anoma Foundation, 2025
/// @notice The Anoma (XAN) token contract implementation version 1.
/// @custom:security-contact security@anoma.foundation
contract XanV1 is
    IXanV1,
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20BurnableUpgradeable,
    UUPSUpgradeable
{
    using Voting for Voting.Data;
    using Council for Council.Data;

    /// @notice A struct containing data associated with the current implementation.
    /// @param lockingData The state associated with the locking mechanism for the current implementation.
    /// @param votingData  The state associated with the voting mechanism for the current implementation.
    /// @param councilData The state associated with the governance council for the current implementation.
    struct ImplementationData {
        Locking.Data lockingData;
        Voting.Data votingData;
        Council.Data councilData;
    }

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v1
    struct XanV1Storage {
        mapping(address current => ImplementationData) implementationSpecificData;
    }

    /// @notice The ERC-7201 storage location of the Xan V1 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V1_STORAGE_LOCATION =
        0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    error UnlockedBalanceInsufficient(address sender, uint256 unlockedBalance, uint256 valueToLock);
    error LockedBalanceInsufficient(address sender, uint256 lockedBalance);

    error ImplementationZero();
    error ImplementationNotMostVoted(address notMostVotedImpl);

    error UpgradeNotScheduled(address impl);
    error UpgradeAlreadyScheduled(address impl, uint48 endTime);
    error UpgradeCancellationInvalid(address impl, uint48 endTime);

    error QuorumOrMinLockedSupplyNotReached(address impl);
    error QuorumAndMinLockedSupplyReached(address impl);

    error DelayPeriodNotStarted(uint48 endTime);
    error DelayPeriodNotEnded(uint48 endTime);

    error UnauthorizedCaller(address caller);

    /// @notice Limits functions to be callable only by the governance council address.
    modifier onlyCouncil() {
        _checkCouncil();
        _;
    }

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the XanV1 contract.
    /// @param initialMintRecipient The initial recipient of the minted tokens.
    /// @param council The address of the governance council contract.
    function initializeV1( /* solhint-disable-line comprehensive-interface*/
        address initialMintRecipient,
        address council
    ) external initializer {
        // Initialize inherited contracts
        __ERC20_init({name_: Parameters.NAME, symbol_: Parameters.SYMBOL});
        __ERC20Permit_init({name: Parameters.NAME});
        __ERC20Burnable_init();
        __UUPSUpgradeable_init();

        // Initialize the XanV1 contract
        _mint(initialMintRecipient, Parameters.SUPPLY);
        _getCouncilData().council = council;
    }

    /// @inheritdoc IXanV1
    function lock(uint256 value) external override {
        _lock({account: msg.sender, value: value});
    }

    /// @inheritdoc IXanV1
    function transferAndLock(address to, uint256 value) external override {
        _transfer({from: msg.sender, to: to, value: value});
        _lock({account: to, value: value});
    }

    /// @inheritdoc IXanV1
    function castVote(address proposedImpl) external override {
        address voter = msg.sender;

        Voting.Data storage votingData = _getVotingData();

        // Cast the vote for the proposed implementation
        {
            Voting.Ballot storage ballot = votingData.ballots[proposedImpl];

            // Cache the old votum of the voter.
            uint256 oldVotum = ballot.vota[voter];

            // Cache the locked balance.
            uint256 newVotum = lockedBalanceOf(voter);

            // Revert if the votum is less or equal to the old votum.
            if (newVotum < oldVotum + 1) {
                revert LockedBalanceInsufficient({sender: voter, lockedBalance: newVotum});
            }

            // Calculate the votes that must be added.
            uint256 delta;
            unchecked {
                // Skip the underflow check because `lockedBalance > oldVotum` has been checked before.
                delta = newVotum - oldVotum;
            }

            // Update the votum.
            ballot.vota[voter] = newVotum;

            // Update the total votes.
            ballot.totalVotes += delta;

            emit VoteCast({voter: voter, impl: proposedImpl, value: delta});
        }

        // Update the most voted implementation if it has changed
        {
            address currentMostVotedImpl = votingData.mostVotedImpl;

            // Check if the proposed implementation now has more votes than the current most voted implementation.
            if (votingData.ballots[currentMostVotedImpl].totalVotes < votingData.ballots[proposedImpl].totalVotes) {
                // Update the most voted implementation to the proposed implementation
                votingData.mostVotedImpl = proposedImpl;

                emit MostVotedImplementationUpdated({newMostVotedImpl: proposedImpl});
            }
        }
    }

    /// @inheritdoc IXanV1
    function scheduleVoterBodyUpgrade() external override {
        Voting.Data storage votingData = _getVotingData();

        // Revert if another upgrade is scheduled by the voter body
        if (votingData.isUpgradeScheduled()) {
            revert UpgradeAlreadyScheduled(votingData.scheduledImpl, votingData.scheduledEndTime);
        }

        // Revert if the most voted implementation has not reached quorum
        {
            if (!_isQuorumAndMinLockedSupplyReached(votingData.mostVotedImpl)) {
                revert QuorumOrMinLockedSupplyNotReached(votingData.mostVotedImpl);
            }

            // Schedule the upgrade and emit the associated event.
            votingData.scheduledImpl = votingData.mostVotedImpl;
            votingData.scheduledEndTime = Time.timestamp() + Parameters.DELAY_DURATION;

            emit VoterBodyUpgradeScheduled(votingData.scheduledImpl, votingData.scheduledEndTime);
        }

        // Check if the council has proposed an upgrade and, if so, cancel
        {
            Council.Data storage councilData = _getCouncilData();
            if (councilData.isUpgradeScheduled()) {
                emit CouncilUpgradeVetoed(councilData.scheduledImpl);

                // Reset the scheduled upgrade
                councilData.scheduledImpl = address(0);
                councilData.scheduledEndTime = 0;
            }
        }
    }

    /// @inheritdoc IXanV1
    function cancelVoterBodyUpgrade() external override {
        Voting.Data storage votingData = _getVotingData();

        // Revert if no voter body upgrade is scheduled
        if (!votingData.isUpgradeScheduled()) {
            revert UpgradeNotScheduled(address(0));
        }

        // Check that the delay period is over
        _checkDelayCriterion(votingData.scheduledEndTime);

        // Revert if the scheduled implementation still meets the quorum and minimum locked
        // supply requirements and is still the most voted implementation.
        if (
            _isQuorumAndMinLockedSupplyReached(votingData.scheduledImpl)
                && (votingData.scheduledImpl == votingData.mostVotedImpl)
        ) {
            revert UpgradeCancellationInvalid(votingData.scheduledImpl, votingData.scheduledEndTime);
        }

        emit VoterBodyUpgradeCancelled(votingData.scheduledImpl);

        // Reset the scheduled upgrade
        votingData.scheduledImpl = address(0);
        votingData.scheduledEndTime = 0;
    }

    /// @notice @inheritdoc IXanV1
    function scheduleCouncilUpgrade(address impl) external override onlyCouncil {
        // Revert if a voter body upgrade could be scheduled
        {
            Voting.Data storage votingData = _getVotingData();

            address mostVotedImpl = votingData.mostVotedImpl;

            if (_isQuorumAndMinLockedSupplyReached(mostVotedImpl)) {
                revert QuorumAndMinLockedSupplyReached(mostVotedImpl);
            }
        }

        Council.Data storage councilData = _getCouncilData();

        // Revert if a council upgrade is already scheduled
        if (councilData.isUpgradeScheduled()) {
            revert UpgradeAlreadyScheduled(councilData.scheduledImpl, councilData.scheduledEndTime);
        }

        // Schedule the council upgrade
        councilData.scheduledImpl = impl;
        councilData.scheduledEndTime = Time.timestamp() + Parameters.DELAY_DURATION;

        emit CouncilUpgradeScheduled(councilData.scheduledImpl, councilData.scheduledEndTime);
    }

    /// @notice @inheritdoc IXanV1
    function cancelCouncilUpgrade() external override onlyCouncil {
        Council.Data storage councilData = _getCouncilData();

        // Revert if no council upgrade is scheduled
        if (!councilData.isUpgradeScheduled()) {
            revert UpgradeNotScheduled(address(0));
        }

        emit CouncilUpgradeCancelled(councilData.scheduledImpl);

        // Reset the scheduled upgrade
        councilData.scheduledImpl = address(0);
        councilData.scheduledEndTime = 0;
    }

    /// @notice @inheritdoc IXanV1
    function vetoCouncilUpgrade() external override {
        // Get the most voted implementation.
        address mostVotedImpl = _getVotingData().mostVotedImpl;

        // Revert if the most voted implementation has not reached quorum or the minimum locked supply
        if (!_isQuorumAndMinLockedSupplyReached(mostVotedImpl)) {
            // The voter body has not reached quorum on any implementation.
            // This means that vetoing the council is not allowed.
            revert QuorumOrMinLockedSupplyNotReached(mostVotedImpl);
        }

        Council.Data storage councilData = _getCouncilData();

        emit CouncilUpgradeVetoed(councilData.scheduledImpl);

        // Reset the scheduled upgrade
        councilData.scheduledImpl = address(0);
        councilData.scheduledEndTime = 0;
    }

    /// @inheritdoc IXanV1
    function votum(address voter, address proposedImpl) external view override returns (uint256 votes) {
        votes = _getVotingData().ballots[proposedImpl].vota[voter];
    }

    /// @notice @inheritdoc IXanV1
    function mostVotedImplementation() external view override returns (address mostVotedImpl) {
        mostVotedImpl = _getVotingData().mostVotedImpl;
    }

    /// @notice @inheritdoc IXanV1
    function lockedSupply() public view override returns (uint256 locked) {
        locked = _getLockingData().lockedSupply;
    }

    /// @notice @inheritdoc IXanV1
    function calculateQuorumThreshold() public view override returns (uint256 threshold) {
        threshold = (lockedSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;
    }

    /// @inheritdoc IXanV1
    function totalVotes(address proposedImpl) public view override returns (uint256 votes) {
        votes = _getVotingData().ballots[proposedImpl].totalVotes;
    }

    /// @notice @inheritdoc IXanV1
    function implementation() public view override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    /// @inheritdoc IXanV1
    function scheduledVoterBodyUpgrade() public view override returns (address impl, uint48 endTime) {
        Voting.Data storage votingData = _getVotingData();
        impl = votingData.scheduledImpl;
        endTime = votingData.scheduledEndTime;
    }

    /// @inheritdoc IXanV1
    function scheduledCouncilUpgrade() public view override returns (address impl, uint48 endTime) {
        Council.Data storage councilData = _getCouncilData();
        impl = councilData.scheduledImpl;
        endTime = councilData.scheduledEndTime;
    }

    /// @inheritdoc IXanV1
    function governanceCouncil() public view override returns (address council) {
        council = _getCouncilData().council;
    }

    /// @inheritdoc IXanV1
    function unlockedBalanceOf(address from) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = balanceOf(from) - lockedBalanceOf(from);
    }

    /// @inheritdoc IXanV1
    function lockedBalanceOf(address from) public view override returns (uint256 lockedBalance) {
        lockedBalance = _getLockingData().lockedBalances[from];
    }

    /// @notice Updates the balances. Only the unlocked token balances can be updated, except for the minting case,
    /// where `from == address(0)`.
    /// @param from The address to take the tokens from.
    /// @param to The address to give the tokens to.
    /// @param value The amount of tokens to update that must be unlocked.
    function _update(address from, address to, uint256 value) internal override {
        // Require the unlocked balance to be at least the updated value, except for the minting case,
        // where `from == address(0)`.
        // In this case, tokens are created ex-nihilo and formally sent from `address(0)` to the `to` address
        // without balance checks.
        if (from != address(0)) {
            uint256 unlockedBalance = unlockedBalanceOf(from);

            if (value > unlockedBalance) {
                // solhint-disable-next-line max-line-length
                revert UnlockedBalanceInsufficient({sender: from, unlockedBalance: unlockedBalance, valueToLock: value});
            }
        }

        super._update({from: from, to: to, value: value});
    }

    /// @notice Permanently locks tokens for an account for the current implementation until it gets upgraded.
    /// @param account The account to lock  the tokens for.
    /// @param value The value to be locked.
    function _lock(address account, uint256 value) internal {
        Locking.Data storage data = _getLockingData();

        uint256 unlockedBalance = unlockedBalanceOf(account);
        if (value > unlockedBalance) {
            revert UnlockedBalanceInsufficient({sender: account, unlockedBalance: unlockedBalance, valueToLock: value});
        }

        data.lockedSupply += value;
        data.lockedBalances[account] += value;

        emit Locked({account: account, value: value});
    }

    /// @notice Authorizes an upgrade.
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view override {
        if (newImpl == address(0)) {
            revert ImplementationZero();
        }
        Voting.Data storage votingData = _getVotingData();
        Council.Data storage councilData = _getCouncilData();

        bool isScheduledByVoterBody = (newImpl == votingData.scheduledImpl);
        bool isScheduledByCouncil = (newImpl == councilData.scheduledImpl);

        // The implementation should never be scheduled by both entities.
        assert(!(isScheduledByVoterBody && isScheduledByCouncil));

        // Cache the most voted implementation proposed by the voter body.
        address mostVotedImpl = votingData.mostVotedImpl;

        if (isScheduledByVoterBody) {
            if (newImpl != mostVotedImpl) {
                revert ImplementationNotMostVoted({notMostVotedImpl: newImpl});
            }

            // This check is redundant, but kept for defense in depth.
            if (!_isQuorumAndMinLockedSupplyReached(mostVotedImpl)) {
                revert QuorumOrMinLockedSupplyNotReached(mostVotedImpl);
            }
            _checkDelayCriterion({endTime: votingData.scheduledEndTime});
        } else if (isScheduledByCouncil) {
            // Check if the most voted implementation exists.
            if (mostVotedImpl != address(0)) {
                // Revert if the quorum and minimum locked supply is reached for the most-voted implementation proposed
                // by the voter body and it could therefore could be scheduled.
                if (_isQuorumAndMinLockedSupplyReached(mostVotedImpl)) {
                    revert QuorumAndMinLockedSupplyReached(mostVotedImpl);
                }
            }
            _checkDelayCriterion({endTime: councilData.scheduledEndTime});
        } else {
            revert UpgradeNotScheduled(newImpl);
        }
    }

    /// @notice Throws if the sender is not the governance council.
    function _checkCouncil() internal view {
        if (governanceCouncil() != msg.sender) {
            revert UnauthorizedCaller({caller: msg.sender});
        }
    }

    /// @notice Returns `true` if the quorum and minimum locked supply is reached for a given implementation.
    /// @param impl The implementation to check the quorum criteria for.
    /// @return isReached Whether the quorum and minimum locked supply is reached or not.
    function _isQuorumAndMinLockedSupplyReached(address impl) internal view returns (bool isReached) {
        if (totalVotes(impl) < calculateQuorumThreshold() + 1) {
            return isReached = false;
        }
        if (lockedSupply() < Parameters.MIN_LOCKED_SUPPLY) {
            return isReached = false;
        }
        isReached = true;
    }

    /// @notice Checks if the delay period for a scheduled upgrade has ended and reverts with errors if not.
    /// @param endTime The end time of the delay period to check.
    function _checkDelayCriterion(uint48 endTime) internal view {
        if (endTime == 0) {
            revert DelayPeriodNotStarted(endTime);
        }

        if (Time.timestamp() < endTime) {
            revert DelayPeriodNotEnded(endTime);
        }
    }

    /// @notice Returns the locking data for the current implementation from the contract storage location.
    /// @return lockingData The data associated with locked tokens.
    function _getLockingData() internal view returns (Locking.Data storage lockingData) {
        lockingData = _getXanV1Storage().implementationSpecificData[implementation()].lockingData;
    }

    /// @notice Returns the proposed upgrades from the current implementation from the contract storage location.
    /// @return votingData The data associated with proposed upgrades from the current implementation.
    function _getVotingData() internal view returns (Voting.Data storage votingData) {
        votingData = _getXanV1Storage().implementationSpecificData[implementation()].votingData;
    }

    /// @notice Returns the data of the upgrade proposed by the council from the current implementation
    /// from the contract storage location.
    /// @return councilData The data associated with upgrade proposed by the council from the current implementation.
    function _getCouncilData() internal view returns (Council.Data storage councilData) {
        councilData = _getXanV1Storage().implementationSpecificData[implementation()].councilData;
    }

    /// @notice Returns the storage from the Xan V1 storage location.
    /// @return xanV1Storage The data associated with the Xan V1 token storage.
    function _getXanV1Storage() internal pure returns (XanV1Storage storage xanV1Storage) {
        // solhint-disable no-inline-assembly
        {
            // slither-disable-next-line assembly
            assembly {
                xanV1Storage.slot := _XAN_V1_STORAGE_LOCATION
            }
        }
        // solhint-enable no-inline-assembly
    }
}
