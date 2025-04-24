// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXan} from "./IXan.sol";
import {Parameters} from "./Parameters.sol";

contract Xan is IXan, ERC20Upgradeable, UUPSUpgradeable {
    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v1
    /// @param _proposedUpgrades The upgrade proposed from a current implementation.
    struct XanStorage {
        mapping(address current => ProposedUpgrades) _proposedUpgrades;
    }

    /// @notice A struct containing data associated with a current implementation and proposed upgrades from it.
    /// @param lockedBalances The locked balances associated with the current implementation.
    /// @param lockedTotalSupply The locked total supply associated with the current implementation.
    /// @param ballots The ballots of proposed implementations to upgrade to.
    /// @param ranking The proposed implementations ranking.
    /// @param implCount The count of proposed implementations.
    struct ProposedUpgrades {
        mapping(address owner => uint256) lockedBalances;
        uint256 lockedTotalSupply;
        mapping(address proposedImpl => Ballot) ballots;
        mapping(uint64 rank => address proposedImpl) ranking;
        uint64 implCount;
    }

    /// @notice The vote data of a proposed implementation.
    /// @param vota The vota of the individual voters.
    /// @param totalVotes The total votes casted.
    /// @param rank The voting rank of the implementation
    /// @param  delayEndTime The end time of the delay period.
    /// @param exists Whether the implementation was proposed or not.
    struct Ballot {
        mapping(address voter => uint256 votes) vota;
        uint256 totalVotes;
        uint64 rank;
        uint48 delayEndTime;
        bool exists;
    }

    /// @notice The ERC-7201 storage location of the contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`
    // solhint-disable-next-line max-line-length
    bytes32 internal constant _XAN_STORAGE_LOCATION = 0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    error InsufficientUnlockedBalance(address sender, uint256 unlockedBalance, uint256 needed);
    error InsufficientLockedBalance(address sender, uint256 lockedBalance);
    error ImplementationNotMostVoted(address newImpl, address mostVotedImplementation);
    error ImplementationZeroAddress(address invalidImpl);
    error DelayPeriodNotStarted(address newImpl);
    error DelayPeriodNotEnded(address newImpl);
    error QuorumNotReached(address newImpl);
    error ImplementationRankNotExistent(uint64 implCount, uint64 rank);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy.
    // solhint-disable-next-line comprehensive-interface
    function initialize(address initialOwner) external virtual initializer {
        __Xan_init(initialOwner);
    }

    /// @inheritdoc IXan
    function lock(uint256 value) external override {
        address owner = msg.sender;
        uint256 unlockedBalance = unlockedBalanceOf(owner);

        if (value > unlockedBalance) {
            revert InsufficientUnlockedBalance({sender: owner, unlockedBalance: unlockedBalance, needed: value});
        }

        _lock({to: owner, value: value});
    }

    /// @inheritdoc IXan
    function transferAndLock(address to, uint256 value) external override {
        _transfer({from: msg.sender, to: to, value: value});
        _lock({to: to, value: value});
    }

    /// @inheritdoc IXan
    // solhint-disable-next-line function-max-lines
    function castVote(address proposedImpl) external override {
        address voter = msg.sender;

        ProposedUpgrades storage $ = _getProposedUpgrades();
        Ballot storage ballot = $.ballots[proposedImpl];

        // Check if this implementation is voted on for the first time.
        {
            if (!ballot.exists) {
                ballot.exists = true;
                ballot.rank = $.implCount;

                // Set the rank to the lowest number.
                uint64 rank = $.implCount;
                $.ranking[rank] = proposedImpl;
                ++$.implCount;
            }
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

        // Check if the implementation has a rank larger than zero.
        if (ballot.rank > 0) {
            uint64 nextRank = ballot.rank - 1;
            address nextImpl = $.ranking[nextRank];
            uint256 nextVotes = $.ballots[nextImpl].totalVotes;

            // Check if the next better ranked implementation has less votes
            while (ballot.totalVotes > nextVotes) {
                // Switch the ranking
                $.ranking[nextRank] = proposedImpl;
                $.ranking[ballot.rank] = nextImpl;

                $.ballots[nextImpl].rank = ballot.rank;
                ballot.rank = nextRank;

                if (ballot.rank > 0) {
                    --nextRank;
                    nextImpl = $.ranking[nextRank];
                    nextVotes = $.ballots[nextImpl].totalVotes;
                } else {
                    break;
                }
            }
        }

        emit VoteCast({voter: voter, implementation: proposedImpl, value: delta});
    }

    /// @inheritdoc IXan
    // solhint-disable-next-line function-max-lines
    function revokeVote(address proposedImpl) external override {
        address voter = msg.sender;

        ProposedUpgrades storage $ = _getProposedUpgrades();
        Ballot storage ballot = $.ballots[proposedImpl];

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // Set the votum of the voter to zero.
        ballot.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        ballot.totalVotes -= oldVotum;

        // Eventually update the ranking
        {
            uint64 maxRank = $.implCount - 1;

            // Check if the implementation has a rank lower than the highest rank.
            if (ballot.rank < maxRank) {
                uint64 nextRank = ballot.rank + 1;
                address nextImpl = $.ranking[nextRank];
                uint256 nextVotes = $.ballots[nextImpl].totalVotes;

                // While
                while (ballot.totalVotes < nextVotes + 1) {
                    // Switch ranks
                    $.ranking[nextRank] = proposedImpl;
                    $.ranking[ballot.rank] = nextImpl;

                    $.ballots[nextImpl].rank = ballot.rank;
                    ballot.rank = nextRank;

                    if (ballot.rank < maxRank) {
                        ++nextRank;
                        nextImpl = $.ranking[nextRank];
                        nextVotes = $.ballots[nextImpl].totalVotes;
                    } else {
                        break;
                    }
                }
            }
        }

        emit VoteRevoked({voter: voter, implementation: proposedImpl, value: oldVotum});
    }

    /// @inheritdoc IXan
    function startDelayPeriod(address proposedImpl) external override {
        // Check that all upgrade criteria are met before.
        checkUpgradeCriteria(proposedImpl);

        Ballot storage ballot = _getProposedUpgrades().ballots[proposedImpl];

        uint48 startTime = Time.timestamp();

        if (ballot.delayEndTime != 0) {
            revert DelayPeriodNotStarted(proposedImpl);
        }

        ballot.delayEndTime = startTime + delayDuration();

        emit DelayStarted({implementation: proposedImpl, startTime: startTime, endTime: ballot.delayEndTime});
    }

    /// @inheritdoc IXan
    function totalVotes(address proposedImpl) external view override returns (uint256 votes) {
        votes = _getProposedUpgrades().ballots[proposedImpl].totalVotes;
    }

    /// @notice @inheritdoc IXan
    // slither-disable-next-line dead-code
    function lockedTotalSupply() external view override returns (uint256 lockedSupply) {
        lockedSupply = _getProposedUpgrades().lockedTotalSupply;
    }

    /// @notice @inheritdoc IXan
    function implementation() public view override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    /// @notice @inheritdoc IXan
    function implementationRank(uint64 rank) public view override returns (address rankedImplementation) {
        ProposedUpgrades storage $ = _getProposedUpgrades();
        uint64 count = $.implCount;

        if (count == 0 || rank > count - 1) {
            revert ImplementationRankNotExistent({implCount: count, rank: rank});
        }

        rankedImplementation = $.ranking[rank];
    }

    /// @notice @inheritdoc IXan
    function checkUpgradeCriteria(address proposedImpl) public view override {
        // TODO remove?
        if (proposedImpl == address(0)) {
            revert ImplementationZeroAddress(address(0));
        }

        // Check that the quorum for the new implementation is reached.
        if (!_isQuorumReached(proposedImpl)) {
            revert QuorumNotReached(proposedImpl);
        }

        // Check that the new implementation is the most voted implementation.
        address mostVotedImplementation = _getProposedUpgrades().ranking[0];

        if (proposedImpl != mostVotedImplementation) {
            revert ImplementationNotMostVoted({newImpl: proposedImpl, mostVotedImplementation: mostVotedImplementation});
        }
    }

    /// @notice @inheritdoc IXan
    function checkDelayPeriod(address newImpl) public view override {
        uint48 delayEndTime = _getProposedUpgrades().ballots[newImpl].delayEndTime;

        if (delayEndTime == 0) revert DelayPeriodNotStarted(newImpl);

        if (Time.timestamp() < delayEndTime) {
            revert DelayPeriodNotEnded(newImpl);
        }
    }

    /// @inheritdoc IXan
    function unlockedBalanceOf(address from) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = balanceOf(from) - lockedBalanceOf(from);
    }

    /// @inheritdoc IXan
    function lockedBalanceOf(address from) public view override returns (uint256 lockedBalance) {
        lockedBalance = _getProposedUpgrades().lockedBalances[from];
    }

    function delayDuration() public pure override returns (uint32 duration) {
        duration = Parameters.DELAY_DURATION;
    }

    function __Xan_init(address initialOwner) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained("Anoma Token", "Xan");
        __UUPSUpgradeable_init_unchained();

        __Xan_init_unchained(initialOwner);
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function __Xan_init_unchained(address initialOwner) internal onlyInitializing {
        _mint(initialOwner, Parameters.SUPPLY);
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal override {
        // Allow only unlocked balances to be updated.
        if (from != address(0)) {
            uint256 unlockedBalance = unlockedBalanceOf(from);

            if (value > unlockedBalance) {
                revert InsufficientUnlockedBalance({sender: from, unlockedBalance: unlockedBalance, needed: value});
            }
        }

        super._update({from: from, to: to, value: value});
    }

    function _lock(address to, uint256 value) internal {
        ProposedUpgrades storage $ = _getProposedUpgrades();

        $.lockedTotalSupply += value;
        $.lockedBalances[to] += value;

        emit Locked({owner: to, value: value});
    }

    /// @notice Checks if the quorum is reached for a new implementation.
    /// @param proposedImpl The new implementation to check.
    /// @return reached Whether quorum for the new implementation is reached.
    function _isQuorumReached(address proposedImpl) internal view returns (bool reached) {
        reached = _getProposedUpgrades().ballots[proposedImpl].totalVotes > Parameters.QUORUM;
    }

    /// @notice Authorizes an upgrade.
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view virtual override {
        checkDelayPeriod(newImpl);

        checkUpgradeCriteria(newImpl);
    }

    /// @notice Returns the upgrade data from the contract storage location.
    /// @return upgradeData The upgrade data associated with the current implementation.
    function _getProposedUpgrades() private view returns (ProposedUpgrades storage upgradeData) {
        XanStorage storage $;

        // solhint-disable no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            $.slot := _XAN_STORAGE_LOCATION
        }
        // solhint-enable no-inline-assembly

        upgradeData = $._proposedUpgrades[implementation()];
    }
}
