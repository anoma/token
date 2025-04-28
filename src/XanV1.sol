// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanV1} from "./interfaces/IXanV1.sol";
import {Parameters} from "./libs/Parameters.sol";
import {Ranking} from "./libs/Ranking.sol";

contract XanV1 is IXanV1, Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, UUPSUpgradeable {
    using Ranking for Ranking.ProposedUpgrades;

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.XanV1.v1
    /// @param proposedUpgrades The upgrade proposed from a current implementation.
    struct XanV1Storage {
        mapping(address current => Ranking.ProposedUpgrades) proposedUpgrades;
    }

    /// @notice The ERC-7201 storage location of the contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V1_STORAGE_LOCATION =
        0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    error UnlockedBalanceInsufficient(address sender, uint256 unlockedBalance, uint256 valueToLock);
    error LockedBalanceInsufficient(address sender, uint256 lockedBalance);
    error ImplementationRankNonExistent(uint48 limit, uint48 rank);
    error ImplementationNotRankedBest(address expected, address actual);
    error ImplementationNotDelayed(address expected, address actual);
    error UpgradeDelayNotResettable(address impl);
    error QuorumNotReached(address proposedImpl);
    error DelayPeriodNotStarted();
    error DelayPeriodAlreadyStarted(address delayedUpgradeImpl);
    error DelayPeriodNotEnded();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy.
    /// @param initialOwner The initial owner of the minted tokens.
    // solhint-disable-next-line comprehensive-interface
    function initialize(address initialOwner) external virtual initializer {
        __XanV1_init(initialOwner);
    }

    /// @inheritdoc IXanV1
    function lock(uint256 value) external virtual override {
        _lock({account: msg.sender, value: value});
    }

    /// @inheritdoc IXanV1
    function transferAndLock(address to, uint256 value) external virtual override {
        _transfer({from: msg.sender, to: to, value: value});
        _lock({account: to, value: value});
    }

    /// @inheritdoc IXanV1
    function castVote(address proposedImpl) external virtual override {
        address voter = msg.sender;

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        Ranking.Ballot storage ballot = $.ballots[proposedImpl];

        if (!ballot.exists) {
            $.assignWorstRank(proposedImpl);
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
        $.bubbleUp(proposedImpl);

        emit VoteCast({voter: voter, implementation: proposedImpl, value: delta});
    }

    /// @inheritdoc IXanV1
    function revokeVote(address proposedImpl) external virtual override {
        address voter = msg.sender;

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        Ranking.Ballot storage ballot = $.ballots[proposedImpl];

        // Cache the old votum of the voter.
        uint256 oldVotum = ballot.vota[voter];

        // TODO! Add check to see if votes > 0. This will prevent `VoteRevoked` from being emitted for no reason.

        // Set the votum of the voter to zero.
        ballot.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        ballot.totalVotes -= oldVotum;

        // Bubble the proposed implementation down in the ranking.
        $.bubbleDown(proposedImpl);

        emit VoteRevoked({voter: voter, implementation: proposedImpl, value: oldVotum});
    }

    /// @inheritdoc IXanV1
    function startUpgradeDelay(address proposedImpl) external virtual override {
        // Check that all upgrade criteria are met before starting the delay.
        _checkUpgradeCriteria(proposedImpl);

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();

        uint48 currentTime = Time.timestamp();

        // Check that the delay period hasn't been started yet by
        // ensuring that no end time and implementation has been set.
        if ($.delayEndTime != 0 && $.delayedUpgradeImpl != address(0)) {
            revert DelayPeriodAlreadyStarted($.delayedUpgradeImpl);
        }

        // Set the end time and emit the associated event.
        $.delayEndTime = currentTime + Parameters.DELAY_DURATION;
        $.delayedUpgradeImpl = proposedImpl;

        emit DelayStarted({implementation: proposedImpl, startTime: currentTime, endTime: $.delayEndTime});
    }

    /// @inheritdoc IXanV1
    function resetUpgradeDelay(address losingImpl) external override {
        _checkDelayCriterion(losingImpl);

        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();

        // Check that the quorum for the new implementation is reached.
        if (_isQuorumReached(losingImpl) && losingImpl == $.ranking[0]) {
            revert UpgradeDelayNotResettable(losingImpl);
        }
        // Reset the delay
        $.delayEndTime = 0;
        $.delayedUpgradeImpl = address(0);

        emit DelayReset({implementation: losingImpl});
    }

    /// @notice @inheritdoc IXanV1
    function lockedTotalSupply() external view virtual override returns (uint256 lockedSupply) {
        lockedSupply = _getProposedUpgrades().lockedTotalSupply;
    }

    /// @notice @inheritdoc IXanV1
    function calculateQuorum() public view override returns (uint256 calculatedQuorum) {
        calculatedQuorum = (totalSupply() * Parameters.QUORUM_RATIO_NUMERATOR) / Parameters.QUORUM_RATIO_DENOMINATOR;
    }

    /// @inheritdoc IXanV1
    function totalVotes(address proposedImpl) public view virtual override returns (uint256 votes) {
        votes = _getProposedUpgrades().ballots[proposedImpl].totalVotes;
    }

    /// @notice @inheritdoc IXanV1
    function implementation() public view virtual override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    /// @notice @inheritdoc IXanV1
    function proposedImplementationByRank(uint48 rank)
        public
        view
        virtual
        override
        returns (address rankedImplementation)
    {
        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();
        uint48 implCount = $.implCount;

        if (implCount == 0 || rank > implCount - 1) {
            revert ImplementationRankNonExistent({limit: implCount, rank: rank});
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

    /// @inheritdoc IXanV1

    function delayedUpgradeImplementation() external view override returns (address delayedImpl) {
        delayedImpl = _getProposedUpgrades().delayedUpgradeImpl;
    }

    /// @inheritdoc IXanV1

    function delayEndTime() external view override returns (uint48 endTime) {
        endTime = _getProposedUpgrades().delayEndTime;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __XanV1_init(address initialOwner) internal onlyInitializing {
        __Context_init_unchained();
        __ERC20_init_unchained("Anoma Token", "Xan");
        __ERC20Burnable_init();
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
        // TODO! Check if the `address(0)` check is necessary here
        // Allow only unlocked balances to be updated.
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
        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();

        uint256 unlockedBalance = unlockedBalanceOf(account);
        if (value > unlockedBalance) {
            revert UnlockedBalanceInsufficient({sender: account, unlockedBalance: unlockedBalance, valueToLock: value});
        }

        $.lockedTotalSupply += value;
        $.lockedBalances[account] += value;

        emit Locked({account: account, value: value});
    }

    /// @notice Authorizes an upgrade.
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view virtual override {
        _checkDelayCriterion(newImpl);

        _checkUpgradeCriteria(newImpl);
    }

    /// @notice Checks if the criteria to upgrade to the new implementation are met and reverts with errors if not.
    /// @param impl The implementation to check the upgrade criteria for.
    function _checkUpgradeCriteria(address impl) internal view virtual {
        // Check that the quorum for the new implementation is reached.
        if (!_isQuorumReached(impl)) {
            revert QuorumNotReached(impl);
        }

        // Check that the new implementation is the most voted implementation.
        address bestRankedImpl = _getProposedUpgrades().ranking[0];

        if (impl != bestRankedImpl) {
            revert ImplementationNotRankedBest({expected: bestRankedImpl, actual: impl});
        }
    }

    function _isQuorumReached(address impl) internal view virtual returns (bool isReached) {
        isReached = totalVotes(impl) > calculateQuorum();
    }

    /// @notice Checks if the delay period has ended and reverts with errors if not.
    function _checkDelayCriterion(address impl) internal view virtual {
        Ranking.ProposedUpgrades storage $ = _getProposedUpgrades();

        if ($.delayEndTime == 0) {
            revert DelayPeriodNotStarted();
        }

        if (Time.timestamp() < $.delayEndTime) {
            revert DelayPeriodNotEnded();
        }

        if (impl != $.delayedUpgradeImpl) {
            revert ImplementationNotDelayed({expected: $.delayedUpgradeImpl, actual: impl});
        }
    }

    /// @notice Returns the proposed upgrades from the from current implementation from the contract storage location.
    /// @return proposedUpgrades The data associated with proposed upgrades from current implementation.
    function _getProposedUpgrades() internal view virtual returns (Ranking.ProposedUpgrades storage proposedUpgrades) {
        proposedUpgrades = _getXanV1Storage().proposedUpgrades[implementation()];
    }

    /// @notice Returns the storage from the contract storage location.
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
