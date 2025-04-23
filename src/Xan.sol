// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXan} from "./IXan.sol";
import {Parameters} from "./Parameters.sol";

contract Xan is IXan, UUPSUpgradeable, ERC20Upgradeable {
    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v1
    /// @param _upgradeData The upgrade data associated with an implementation to upgrade from.
    struct XanStorage {
        mapping(address current => UpgradeData) _upgradeData;
    }

    /// @notice A struct containing data associated with a current implementation and proposed implementations to upgrade to.
    /// @param lockedBalances The locked balances associated with the current implementation.
    /// @param lockedTotalSupply The locked total supply associated with the current implementation.
    /// @param voteData The vote data for a proposed implementations to upgrade to.
    /// @param implementationByRank The proposed implementations ranking.
    /// @param implCount The count of proposed implementations.
    struct UpgradeData {
        mapping(address owner => uint256) lockedBalances;
        uint256 lockedTotalSupply;
        mapping(address proposed => VoteData) voteData;
        mapping(uint64 rank => address) implementationByRank;
        uint64 implCount;
    }

    /// @notice The vote data of a proposed implementation.
    /// @param vota The vota of the individual voters.
    /// @param totalVotes The total votes casted.
    /// @param rank The voting rank of the implementation
    /// @param  delayEndTime The end time of the delay period.
    /// @param exists Whether the implementation was proposed or not.
    struct VoteData {
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

    /// @notice The delay duration until an upgrade to a new implementation can take place.
    uint32 internal constant _DELAY_DURATION = 2 weeks;

    error InsufficientUnlockedBalance(address sender, uint256 unlockedBalance, uint256 needed);
    error InsufficientLockedBalance(address sender, uint256 lockedBalance);
    error ImplementationNotMostVoted(address newImplementation, address mostVotedImplementation);
    error ImplementationZeroAddress(address invalidImplementation);
    error DelayPeriodNotStarted(address newImplementation);
    error DelayPeriodNotEnded(address newImplementation);
    error QuorumNotReached(address newImplementation);
    error ImplementationRankNotExistent(uint64 implementationCount, uint64 rank);

    // TODO rename newImpl to proposedImpl

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    function initialize(address initialOwner) external initializer {
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
    function castVote(address newImplementation) external override {
        address voter = msg.sender;

        UpgradeData storage $ = _getUpgradeData();
        VoteData storage _voteData = $.voteData[newImplementation];

        // Check if this implementation is voted on for the first time.
        {
            if (!_voteData.exists) {
                _voteData.exists = true;
                _voteData.rank = $.implCount;

                // Set the rank to the lowest number.
                uint64 rank = $.implCount;
                $.implementationByRank[rank] = newImplementation;
                ++$.implCount;
            }
        }

        // Cache the old votum of the voter.
        uint256 oldVotum = _voteData.vota[voter];

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
        _voteData.vota[voter] = lockedBalance;

        // Update the total votes.
        _voteData.totalVotes += delta;

        // Check if the implementation has a rank larger than zero.
        if (_voteData.rank > 0) {
            uint64 nextRank = _voteData.rank - 1;
            address nextImpl = $.implementationByRank[nextRank];
            uint256 nextVotes = $.voteData[nextImpl].totalVotes;

            // Check if the next better ranked implementation has less votes
            while (_voteData.totalVotes > nextVotes) {
                // Switch the ranking
                $.implementationByRank[nextRank] = newImplementation;
                $.implementationByRank[_voteData.rank] = nextImpl;

                $.voteData[nextImpl].rank = _voteData.rank;
                _voteData.rank = nextRank;

                if (_voteData.rank > 0) {
                    --nextRank;
                    nextImpl = $.implementationByRank[nextRank];
                    nextVotes = $.voteData[nextImpl].totalVotes;
                } else {
                    break;
                }
            }
        }

        emit VoteCast({voter: voter, implementation: newImplementation, value: delta});
    }

    /// @inheritdoc IXan
    // solhint-disable-next-line function-max-lines
    function revokeVote(address newImplementation) external override {
        address voter = msg.sender;

        UpgradeData storage $ = _getUpgradeData();
        VoteData storage _voteData = $.voteData[newImplementation];

        // Cache the old votum of the voter.
        uint256 oldVotum = _voteData.vota[voter];

        // Set the votum of the voter to zero.
        _voteData.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        _voteData.totalVotes -= oldVotum;

        // Eventually update the ranking
        {
            uint64 maxRank = $.implCount - 1;

            // Check if the implementation has a rank lower than the highest rank.
            if (_voteData.rank < maxRank) {
                uint64 nextRank = _voteData.rank + 1;
                address nextImpl = $.implementationByRank[nextRank];
                uint256 nextVotes = $.voteData[nextImpl].totalVotes;

                // While
                while (_voteData.totalVotes < nextVotes + 1) {
                    // Switch ranks
                    $.implementationByRank[nextRank] = newImplementation;
                    $.implementationByRank[_voteData.rank] = nextImpl;

                    $.voteData[nextImpl].rank = _voteData.rank;
                    _voteData.rank = nextRank;

                    if (_voteData.rank < maxRank) {
                        ++nextRank;
                        nextImpl = $.implementationByRank[nextRank];
                        nextVotes = $.voteData[nextImpl].totalVotes;
                    } else {
                        break;
                    }
                }
            }
        }

        emit VoteRevoked({voter: voter, implementation: newImplementation, value: oldVotum});
    }

    /// @inheritdoc IXan
    function startDelayPeriod(address newImplementation) external override {
        // Check that all upgrade criteria are met before.
        checkUpgradeCriteria(newImplementation);

        VoteData storage _voteData = _getUpgradeData().voteData[newImplementation];

        uint48 startTime = Time.timestamp();

        if (_voteData.delayEndTime != 0) {
            revert DelayPeriodNotStarted(newImplementation);
        }

        _voteData.delayEndTime = startTime + delayDuration();

        emit DelayStarted({implementation: newImplementation, startTime: startTime, endTime: _voteData.delayEndTime});
    }

    /// @inheritdoc IXan
    function totalVotes(address newImplementation) external view override returns (uint256 votes) {
        votes = _getUpgradeData().voteData[newImplementation].totalVotes;
    }

    /// @notice @inheritdoc IXan
    // slither-disable-next-line dead-code
    function lockedTotalSupply() external view override returns (uint256 lockedSupply) {
        lockedSupply = _getUpgradeData().lockedTotalSupply;
    }

    function implementation() public view override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    function implementationByRank(uint64 rank) public view override returns (address rankedImplementation) {
        UpgradeData storage $ = _getUpgradeData();
        uint64 count = $.implCount;

        if (count == 0 || rank > count - 1) {
            revert ImplementationRankNotExistent({implementationCount: count, rank: rank});
        }

        rankedImplementation = $.implementationByRank[rank];
    }

    /// @notice @inheritdoc IXan
    function checkUpgradeCriteria(address newImplementation) public view override {
        // TODO remove?
        if (newImplementation == address(0)) {
            revert ImplementationZeroAddress(address(0));
        }

        // Check that the quorum for the new implementation is reached.
        if (!_isQuorumReached(newImplementation)) {
            revert QuorumNotReached(newImplementation);
        }

        // Check that the new implementation is the most voted implementation.
        address mostVotedImplementation = _getUpgradeData().implementationByRank[0];

        if (newImplementation != mostVotedImplementation) {
            revert ImplementationNotMostVoted({
                newImplementation: newImplementation,
                mostVotedImplementation: mostVotedImplementation
            });
        }
    }

    /// @notice @inheritdoc IXan
    function checkDelayPeriod(address newImplementation) public view override {
        uint48 delayEndTime = _getUpgradeData().voteData[newImplementation].delayEndTime;

        if (delayEndTime == 0) revert DelayPeriodNotStarted(newImplementation);

        if (Time.timestamp() < delayEndTime) {
            revert DelayPeriodNotEnded(newImplementation);
        }
    }

    /// @inheritdoc IXan
    function unlockedBalanceOf(address from) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = balanceOf(from) - lockedBalanceOf(from);
    }

    /// @inheritdoc IXan
    function lockedBalanceOf(address from) public view override returns (uint256 lockedBalance) {
        lockedBalance = _getUpgradeData().lockedBalances[from];
    }

    function delayDuration() public pure override returns (uint32 duration) {
        duration = _DELAY_DURATION;
    }

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    // solhint-disable-next-line func-name-mixedcase
    function __Xan_init(address initialOwner) internal onlyInitializing {
        __ERC20_init("Anoma", "Xan");
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

        super._update(from, to, value);
    }

    function _lock(address to, uint256 value) internal {
        UpgradeData storage $ = _getUpgradeData();

        $.lockedTotalSupply += value;
        $.lockedBalances[to] += value;

        emit Locked({owner: to, value: value});
    }

    /// @notice Checks if the quorum is reached for a new implementation.
    /// @param newImplementation The new implementation to check.
    /// @return reached Whether quorum for the new implementation is reached.
    function _isQuorumReached(address newImplementation) internal view returns (bool reached) {
        reached = _getUpgradeData().voteData[newImplementation].totalVotes > Parameters.QUORUM;
    }

    /// @notice Authorizes an upgrade.
    /// @param newImplementation The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImplementation) internal view override {
        checkDelayPeriod(newImplementation);

        checkUpgradeCriteria(newImplementation);
    }

    /// @notice Returns the upgrade data from the contract storage location.
    /// @return upgradeData The upgrade data associated with the current implementation.
    function _getUpgradeData() private view returns (UpgradeData storage upgradeData) {
        XanStorage storage $;

        // solhint-disable no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            $.slot := _XAN_STORAGE_LOCATION
        }
        // solhint-enable no-inline-assembly

        upgradeData = $._upgradeData[implementation()];
    }
}
