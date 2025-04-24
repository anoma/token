// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanV1} from "./interfaces/IXanV1.sol";
import {Parameters} from "./libs/Parameters.sol";
import {Ranking} from "./libs/Ranking.sol";

contract XanV1 is IXanV1, ERC20Upgradeable, UUPSUpgradeable {
    using Ranking for Ranking.ProposedUpgrades;

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.XanV1.v1
    /// @param proposedUpgrades The upgrade proposed from a current implementation.
    struct XanStorage {
        mapping(address current => Ranking.ProposedUpgrades) proposedUpgrades;
    }

    /// @notice The ERC-7201 storage location of the contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`
    // solhint-disable-next-line max-line-length
    bytes32 internal constant _XAN_STORAGE_LOCATION = 0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    error InsufficientUnlockedBalance(address sender, uint256 unlockedBalance, uint256 valueToLock);
    error InsufficientLockedBalance(address sender, uint256 lockedBalance);
    error ImplementationNotWinning(address impl, address winningImpl);
    error DelayPeriodNotStarted(address proposedImpl);
    error DelayPeriodAlreadyStarted(address proposedImpl);
    error DelayPeriodNotEnded(address proposedImpl);
    error QuorumNotReached(address proposedImpl);
    error ImplementationRankNonExistent(uint64 implCount, uint64 rank);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy.
    // solhint-disable-next-line comprehensive-interface
    function initialize(address initialOwner) external virtual initializer {
        __XanV1_init(initialOwner);
    }

    /// @inheritdoc IXanV1
    function lock(uint256 value) external virtual override {
        address owner = msg.sender;
        uint256 unlockedBalance = unlockedBalanceOf(owner);

        if (value > unlockedBalance) {
            revert InsufficientUnlockedBalance({sender: owner, unlockedBalance: unlockedBalance, valueToLock: value});
        }

        _lock({to: owner, value: value});
    }

    /// @inheritdoc IXanV1
    function transferAndLock(address to, uint256 value) external virtual override {
        _transfer({from: msg.sender, to: to, value: value});
        _lock({to: to, value: value});
    }

    /// @inheritdoc IXanV1
    function castVote(address proposedImpl) external virtual override {
        address voter = msg.sender;

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        Ranking.Ballot storage ballot = $.ballots[proposedImpl];

        if (!ballot.exists) {
            $.assignHighestRank(proposedImpl);
        }

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // Cache the locked balance.
        uint256 lockedBalance = lockedBalanceOf(voter);

        // Check that the locked balance is larger than the old votum.
        if (lockedBalance < oldVotum + 1) {
            revert InsufficientLockedBalance({sender: voter, lockedBalance: lockedBalance});
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

        // Update the ranking. Check if lower ranked implementation should ranked higher.
        $.updateRanking(proposedImpl, Ranking.SearchDirection.Lower);

        emit VoteCast({voter: voter, implementation: proposedImpl, value: delta});
    }

    /// @inheritdoc IXanV1
    function revokeVote(address proposedImpl) external virtual override {
        address voter = msg.sender;

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        Ranking.Ballot storage ballot = $.ballots[proposedImpl];

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // Set the votum of the voter to zero.
        ballot.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        ballot.totalVotes -= oldVotum;

        // Update the ranking. Check if higher ranked implementation should ranked lower.
        $.updateRanking(proposedImpl, Ranking.SearchDirection.Higher);

        emit VoteRevoked({voter: voter, implementation: proposedImpl, value: oldVotum});
    }

    /// @inheritdoc IXanV1
    function startDelayPeriod(address proposedImpl) external virtual override {
        // Check that all upgrade criteria are met before starting the delay.
        _checkUpgradeCriteria(proposedImpl);

        Ranking.Ballot storage ballot = _getProposedUpgrades().ballots[proposedImpl];

        uint48 currentTime = Time.timestamp();

        // Check that the delay period hasn't been started yet by ensuring that no end time has been set.
        if (ballot.delayEndTime != 0) {
            revert DelayPeriodAlreadyStarted(proposedImpl);
        }

        // Set the end time and emit the associated event.
        ballot.delayEndTime = currentTime + Parameters.DELAY_DURATION;

        emit DelayStarted({implementation: proposedImpl, startTime: currentTime, endTime: ballot.delayEndTime});
    }

    /// @inheritdoc IXanV1
    function totalVotes(address proposedImpl) external view virtual override returns (uint256 votes) {
        votes = _getProposedUpgrades().ballots[proposedImpl].totalVotes;
    }

    /// @notice @inheritdoc IXanV1
    // slither-disable-next-line dead-code
    function lockedTotalSupply() external view virtual override returns (uint256 lockedSupply) {
        lockedSupply = _getProposedUpgrades().lockedTotalSupply;
    }

    /// @notice @inheritdoc IXanV1
    function implementation() public view virtual override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    /// @notice @inheritdoc IXanV1
    function proposedImplementationByRank(uint64 rank)
        public
        view
        virtual
        override
        returns (address rankedImplementation)
    {
        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        uint64 implCount = $.implCount;

        if (implCount == 0 || rank > implCount - 1) {
            revert ImplementationRankNonExistent({implCount: implCount, rank: rank});
        }

        rankedImplementation = $.ranking[rank];
    }

    /// @inheritdoc IXanV1
    function unlockedBalanceOf(address from) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = balanceOf(from) - lockedBalanceOf(from);
    }

    /// @inheritdoc IXanV1
    function lockedBalanceOf(address from) public view override returns (uint256 lockedBalance) {
        lockedBalance = _getProposedUpgrades().lockedBalances[from];
    }

    // solhint-disable-next-line func-name-mixedcase
    function __XanV1_init(address initialOwner) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained("Anoma Token", "Xan");
        __UUPSUpgradeable_init_unchained();

        __XanV1_init_unchained(initialOwner);
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    // solhint-disable-next-line func-name-mixedcase
    function __XanV1_init_unchained(address initialOwner) internal onlyInitializing {
        _mint(initialOwner, Parameters.SUPPLY);
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal override {
        // Allow only unlocked balances to be updated.
        if (from != address(0)) {
            uint256 unlockedBalance = unlockedBalanceOf(from);

            if (value > unlockedBalance) {
                // solhint-disable-next-line max-line-length
                revert InsufficientUnlockedBalance({sender: from, unlockedBalance: unlockedBalance, valueToLock: value});
            }
        }

        super._update({from: from, to: to, value: value});
    }

    function _lock(address to, uint256 value) internal {
        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();

        $.lockedTotalSupply += value;
        $.lockedBalances[to] += value;

        emit Locked({owner: to, value: value});
    }

    /// @notice Authorizes an upgrade.
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view virtual override {
        _checkDelayPeriod(newImpl);

        _checkUpgradeCriteria(newImpl);
    }

    /// @notice Checks if the quorum is reached for a new implementation.
    /// @param proposedImpl The new implementation to check.
    /// @return reached Whether quorum for the new implementation is reached.
    function _isQuorumReached(address proposedImpl) internal view returns (bool reached) {
        reached = _getProposedUpgrades().ballots[proposedImpl].totalVotes > Parameters.QUORUM;
    }

    /// @notice Checks if the criteria to upgrade to the new implementation are met and reverts with errors if not.
    /// @param impl The implementation to check the upgrade criteria for.
    function _checkUpgradeCriteria(address impl) internal view virtual {
        // Check that the quorum for the new implementation is reached.
        if (!_isQuorumReached(impl)) {
            revert QuorumNotReached(impl);
        }

        // Check that the new implementation is the most voted implementation.
        address winningImpl = _getProposedUpgrades().ranking[0];

        if (impl != winningImpl) {
            revert ImplementationNotWinning({impl: impl, winningImpl: winningImpl});
        }
    }

    /// @notice Checks if the delay period has ended and reverts with errors if not.
    /// @param impl The implementation to check the delay period for.
    function _checkDelayPeriod(address impl) internal view virtual {
        uint48 delayEndTime = _getProposedUpgrades().ballots[impl].delayEndTime;

        if (delayEndTime == 0) revert DelayPeriodNotStarted(impl);

        if (Time.timestamp() < delayEndTime) {
            revert DelayPeriodNotEnded(impl);
        }
    }

    /// @notice Returns the upgrade data from the contract storage location.
    /// @return proposedUpgrades The data associated with proposed upgrades from current implementation.
    function _getProposedUpgrades() private view returns (Ranking.ProposedUpgrades storage proposedUpgrades) {
        XanStorage storage $;

        // solhint-disable no-inline-assembly
        {
            // slither-disable-next-line assembly
            assembly {
                $.slot := _XAN_STORAGE_LOCATION
            }
        }
        // solhint-enable no-inline-assembly

        proposedUpgrades = $.proposedUpgrades[implementation()];
    }
}
