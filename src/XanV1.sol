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

contract XanV1 is
    IXanV1,
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20BurnableUpgradeable,
    UUPSUpgradeable
{
    using Voting for Voting.Data;

    /// @notice A struct containing data associated with a current implementation.
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
        // TODO! Revisit
        mapping(address current => ImplementationData) implementationSpecificData;
    }

    /// @notice The ERC-7201 storage location of the Xan V1 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V1_STORAGE_LOCATION =
        0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    error UnlockedBalanceInsufficient(address sender, uint256 unlockedBalance, uint256 valueToLock);
    error LockedBalanceInsufficient(address sender, uint256 lockedBalance);
    error NoVotesToRevoke(address sender, address proposedImpl);
    error ImplementationZero();
    error ImplementationAlreadyProposed(address impl);
    error ImplementationRankNonExistent(uint48 limit, uint48 rank);
    error ImplementationNotRankedBest(address expected, address actual);
    error ImplementationNotDelayed(address expected, address actual);

    error UpgradeNotScheduled(address impl);
    error UpgradeAlreadyScheduled(ScheduledUpgrade scheduledImpl);
    error UpgradeCancellationInvalid(ScheduledUpgrade scheduledImpl);

    error MinLockedSupplyNotReached();
    error QuorumNowhereReached(); // TODO remove?
    error QuorumNotReached(address proposedImpl);
    error QuorumReachedForVoterBodyProposedImplementation(address voterBodyProposedImpl);

    error DelayPeriodNotStarted(ScheduledUpgrade scheduledImpl);
    error DelayPeriodNotEnded(ScheduledUpgrade scheduledImpl);

    error UnauthorizedCaller(address caller);

    /// @notice Limits functions to be callable only by the governance council address.
    modifier onlyCouncil() {
        _checkOnlyCouncil();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the XanV1 contract.
    /// @param initialMintRecipient The initial recipient of the minted tokens.
    /// @param council The address of the governance council contract.
    // solhint-disable-next-line comprehensive-interface
    function initializeV1(address initialMintRecipient, address council) external initializer {
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

        Voting.Data storage data = _getVotingData();
        Voting.Ballot storage ballot = data.ballots[proposedImpl];

        if (!ballot.exists) {
            data.assignWorstRank(proposedImpl);
        }

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // Cache the locked balance.
        uint256 lockedBalance = lockedBalanceOf(voter);

        // Check that the locked balance is larger than the old votum.
        if (lockedBalance < oldVotum + 1) {
            revert LockedBalanceInsufficient({sender: voter, lockedBalance: lockedBalance});
        }

        // Calculate the votes that must be added.
        uint256 delta;
        unchecked {
            // Skip the underflow check because `lockedBalance > oldVotum` has been checked before.
            delta = lockedBalance - oldVotum;
        }

        // Update the votum.
        ballot.vota[voter] = lockedBalance;

        // Update the total votes.
        ballot.totalVotes += delta;

        // Bubble the proposed implementation up in the ranking.
        data.bubbleUp(proposedImpl);

        emit VoteCast({voter: voter, implementation: proposedImpl, value: delta});
    }

    /// @inheritdoc IXanV1
    function revokeVote(address proposedImpl) external override {
        address voter = msg.sender;

        Voting.Data storage data = _getVotingData();
        Voting.Ballot storage ballot = data.ballots[proposedImpl];

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // Check if there has been an old votum to revoke.
        if (oldVotum == 0) {
            revert NoVotesToRevoke({sender: voter, proposedImpl: proposedImpl});
        }

        // Set the votum of the voter to zero.
        ballot.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        ballot.totalVotes -= oldVotum;

        // Bubble the proposed implementation down in the ranking.
        data.bubbleDown(proposedImpl);

        emit VoteRevoked({voter: voter, implementation: proposedImpl, value: oldVotum});
    }

    /// @inheritdoc IXanV1
    function scheduleVoterBodyUpgrade(address proposedImpl) external override {
        // Check that all upgrade criteria are met before starting the delay.
        _checkVoterBodyUpgradeCriteria(proposedImpl);

        Voting.Data storage data = _getVotingData();

        // Check that the delay period hasn't been started yet by
        // ensuring that no end time and implementation has been set.
        if (data.scheduledUpgrade.endTime != 0 && data.scheduledUpgrade.impl != address(0)) {
            revert UpgradeAlreadyScheduled(data.scheduledUpgrade);
        }

        // Schedule the upgrade and emit the associated event.
        data.scheduledUpgrade =
            ScheduledUpgrade({impl: proposedImpl, endTime: Time.timestamp() + Parameters.DELAY_DURATION});

        emit VoterBodyUpgradeScheduled(data.scheduledUpgrade);
    }

    /// @inheritdoc IXanV1
    function cancelVoterBodyUpgrade() external override {
        Voting.Data storage data = _getVotingData();

        ScheduledUpgrade memory scheduledUpgrade = data.scheduledUpgrade;

        _checkDelayCriterion(scheduledUpgrade);

        // Check that the quorum for the new implementation is reached.
        // TODO! Add getter for best ranked impl.
        if (_isQuorumReached(scheduledUpgrade.impl) && scheduledUpgrade.impl == data.ranking[0]) {
            revert UpgradeCancellationInvalid(scheduledUpgrade);
        }

        emit VoterBodyUpgradeCancelled(data.scheduledUpgrade);

        // Reset the scheduled upgrade
        data.scheduledUpgrade = ScheduledUpgrade({impl: address(0), endTime: 0});
    }

    /// @notice @inheritdoc IXanV1
    function scheduleCouncilUpgrade(address proposedImpl) external override onlyCouncil {
        Council.Data storage data = _getCouncilData();

        if (data.scheduledUpgrade.impl == proposedImpl) {
            revert ImplementationAlreadyProposed(proposedImpl);
        }

        data.scheduledUpgrade =
            ScheduledUpgrade({impl: proposedImpl, endTime: Time.timestamp() + Parameters.DELAY_DURATION});

        emit CouncilUpgradeScheduled(data.scheduledUpgrade);
    }

    /// @notice @inheritdoc IXanV1
    function cancelCouncilUpgrade() external override onlyCouncil {
        emit CouncilUpgradeCancelled();
        _cancelCouncilUpgrade();
    }

    /// @notice @inheritdoc IXanV1
    function vetoCouncilUpgrade() external override {
        // Get the implementation with the most votes.
        address mostVotedImplementation = _getVotingData().ranking[0];

        // Check if the most voted implementation has reached quorum.
        if (!_isQuorumReached(mostVotedImplementation)) {
            // The voter body has not reached quorum on any implementation.
            // This means that vetoing the council is not possible.
            revert QuorumNowhereReached();
        }

        emit CouncilUpgradeVetoed();

        // Cancel the council upgrade
        _cancelCouncilUpgrade();
    }

    /// @inheritdoc IXanV1
    function votum(address proposedImpl) external view override returns (uint256 votes) {
        votes = _getVotingData().ballots[proposedImpl].vota[msg.sender];
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

    /// @notice @inheritdoc IXanV1
    function proposedImplementationByRank(uint48 rank) public view override returns (address rankedImplementation) {
        Voting.Data storage $ = _getVotingData();
        uint48 implCount = $.implCount;

        if (implCount == 0 || rank > implCount - 1) {
            revert ImplementationRankNonExistent({limit: implCount, rank: rank});
        }

        rankedImplementation = $.ranking[rank];
    }

    /// @inheritdoc IXanV1
    function scheduledVoterBodyUpgrade() public view override returns (ScheduledUpgrade memory scheduledUpgrade) {
        scheduledUpgrade = _getVotingData().scheduledUpgrade;
    }

    /// @inheritdoc IXanV1
    function scheduledCouncilUpgrade() public view override returns (ScheduledUpgrade memory scheduledUpgrade) {
        scheduledUpgrade = _getCouncilData().scheduledUpgrade;
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

    /// @inheritdoc ERC20Upgradeable
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
        Locking.Data storage $ = _getLockingData();

        uint256 unlockedBalance = unlockedBalanceOf(account);
        if (value > unlockedBalance) {
            revert UnlockedBalanceInsufficient({sender: account, unlockedBalance: unlockedBalance, valueToLock: value});
        }

        $.lockedSupply += value;
        $.lockedBalances[account] += value;

        emit Locked({account: account, value: value});
    }

    /// @notice Cancels the scheduled upgrade by the council by resetting it to 0.
    function _cancelCouncilUpgrade() internal {
        _getCouncilData().scheduledUpgrade = ScheduledUpgrade({impl: address(0), endTime: 0});
    }

    /// @notice Authorizes an upgrade.
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view override {
        if (newImpl == address(0)) {
            revert ImplementationZero();
        }

        ScheduledUpgrade memory voterBodyUpgrade = scheduledVoterBodyUpgrade();
        ScheduledUpgrade memory councilUpgrade = scheduledCouncilUpgrade();

        bool isScheduledByVoterBody = (newImpl == voterBodyUpgrade.impl);
        bool isScheduledByCouncil = (newImpl == councilUpgrade.impl);

        if (isScheduledByVoterBody && isScheduledByCouncil) {
            if (voterBodyUpgrade.endTime < councilUpgrade.endTime) {
                _checkDelayCriterion(voterBodyUpgrade);
                _checkVoterBodyUpgradeCriteria(newImpl);
            } else {
                _checkDelayCriterion(councilUpgrade);
                _checkCouncilUpgradeCriteria(newImpl);
            }
            return;
        }

        if (isScheduledByVoterBody) {
            _checkDelayCriterion(voterBodyUpgrade);
            _checkVoterBodyUpgradeCriteria(newImpl);

            return;
        }

        if (isScheduledByCouncil) {
            _checkDelayCriterion(councilUpgrade);
            _checkCouncilUpgradeCriteria(newImpl);

            return;
        }

        revert UpgradeNotScheduled(newImpl);
    }

    /// @notice Throws if the sender is not the governance council.
    function _checkOnlyCouncil() internal view {
        if (governanceCouncil() != msg.sender) {
            revert UnauthorizedCaller({caller: msg.sender});
        }
    }

    /// @notice Checks if the criteria to upgrade to the new implementation proposed by the voter body are met
    /// and reverts with errors if not.
    /// @param impl The implementation to check the upgrade criteria for.
    function _checkVoterBodyUpgradeCriteria(address impl) internal view {
        // Check that the minimal required supply has been locked.
        if (!_isMinLockedSupplyReached()) {
            revert MinLockedSupplyNotReached();
        }

        // Check that the quorum for the new implementation is reached.
        if (!_isQuorumReached(impl)) {
            revert QuorumNotReached(impl);
        }

        // Check that the new implementation is the most voted implementation.
        address bestRankedImpl = _getVotingData().ranking[0];

        if (impl != bestRankedImpl) {
            revert ImplementationNotRankedBest({expected: bestRankedImpl, actual: impl});
        }
    }

    /// @notice Checks if the criteria to upgrade to the new implementation proposed by the governance council are met
    /// and reverts with errors if not.
    /// @param impl The implementation to check the upgrade criteria for.
    // TODO! Change input args.
    function _checkCouncilUpgradeCriteria(address impl) internal view {
        // Get the implementation with the most votes.
        address voterBodyProposedImpl = _getVotingData().ranking[0];

        // Check if it matches the
        if (impl == voterBodyProposedImpl) return; // TODO! Test this logic carefully

        if (_isQuorumReached(voterBodyProposedImpl)) {
            revert QuorumReachedForVoterBodyProposedImplementation(voterBodyProposedImpl);
        }
    }

    /// @notice Returns `true` if the quorum is reached for a particular implementation.
    /// @param impl The implementation to check the quorum criteria for.
    /// @return isReached Whether the quorum is reached or not.
    function _isQuorumReached(address impl) internal view returns (bool isReached) {
        isReached = totalVotes(impl) > calculateQuorumThreshold();
    }

    /// @notice Returns `true` if the quorum is reached for a particular implementation.
    /// @return isReached Whether the minimum locked supply is reached or not.
    function _isMinLockedSupplyReached() internal view returns (bool isReached) {
        isReached = lockedSupply() + 1 > Parameters.MIN_LOCKED_SUPPLY;
    }

    /// @notice Checks if the delay period for a scheduled upgrade has ended and reverts with errors if not.
    /// @param scheduledUpgrade The end time to check.
    function _checkDelayCriterion(ScheduledUpgrade memory scheduledUpgrade) internal view {
        if (scheduledUpgrade.endTime == 0) {
            revert DelayPeriodNotStarted(scheduledUpgrade);
        }

        if (Time.timestamp() < scheduledUpgrade.endTime) {
            revert DelayPeriodNotEnded(scheduledUpgrade);
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
    /// @return proposedUpgrade The data associated with upgrade proposed by the council from the current implementation.
    function _getCouncilData() internal view returns (Council.Data storage proposedUpgrade) {
        proposedUpgrade = _getXanV1Storage().implementationSpecificData[implementation()].councilData;
    }

    /// @notice Returns the storage from the Xan V1 storage location.
    /// @return $ The data associated with Xan token storage.
    function _getXanV1Storage() internal pure returns (XanV1Storage storage $) {
        // solhint-disable no-inline-assembly
        {
            // slither-disable-next-line assembly
            assembly {
                $.slot := _XAN_V1_STORAGE_LOCATION
            }
        }
        // solhint-enable no-inline-assembly
    }
}
