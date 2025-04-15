// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";

import { IXan } from "./IXan.sol";

contract Xan is IXan, UUPSUpgradeable, ERC20Upgradeable {
    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v1
    /// @param _lockedBalances The locked balances associated with the current implementation.
    /// @param _voteData The vote data for new implementations associated with the current implementation.
    /// @param _lockedTotalSupply The locked total supply associated with the current implementation.
    /// @param _mostVotedNewImplementation The most voted new implementation associated with the current implementation.
    struct XanStorage {
        mapping(address currentImplementation => mapping(address owner => uint256)) _lockedBalances;
        mapping(address currentImplementation => mapping(address newImplementation => VoteData)) _voteData;
        mapping(address currentImplementation => uint256) _lockedTotalSupply;
        mapping(address currentImplementation => address) _mostVotedNewImplementation;
    }

    /// @notice The vote data.
    /// @param vota The vota of the individual voters.
    struct VoteData {
        mapping(address voter => uint256 votes) vota;
        uint256 totalVotes;
        uint48 delayEndTime;
    }

    /// @notice The ERC-7201 storage location of the contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`
    bytes32 internal constant _XAN_STORAGE_LOCATION = 0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    /// @notice The delay duration until an upgrade to a new implementation can take place.
    uint32 public constant override DELAY_DURATION = 2 weeks;

    error InsufficientUnlockedBalance(address sender, uint256 unlockedBalance, uint256 needed);
    error InsufficientLockedBalance(address sender, uint256 lockedBalance);
    error ImplementationNotMostVoted(address newImplementation, address mostVotedImplementation);
    error ImplementationZeroAddress(address invalidImplementation);
    error DelayPeriodNotStarted(address newImplementation);
    error DelayPeriodNotEnded(address newImplementation);
    error QuorumNotReached(address newImplementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    function initialize() external initializer {
        __Xan_init();
    }

    /// @inheritdoc IXan
    function lock(uint256 value) external override {
        address owner = msg.sender;

        uint256 unlockedBalance = unlockedBalanceOf(owner);
        if (value > unlockedBalance) {
            revert InsufficientUnlockedBalance({ sender: owner, unlockedBalance: unlockedBalance, needed: value });
        }

        address currentImpl = implementation();
        XanStorage storage $ = _getXanStorage();
        $._lockedTotalSupply[currentImpl] += value;
        $._lockedBalances[currentImpl][owner] += value;

        emit Locked({ owner: owner, value: value });
    }

    /// @inheritdoc IXan
    function castVote(address newImplementation) external override {
        address voter = msg.sender;
        VoteData storage _voteData = _getVoteData(newImplementation);

        // Cache the old votum of the voter.
        uint256 oldVotum = _voteData.vota[voter];

        // Cache the locked balance.
        uint256 lockedBalance = lockedBalanceOf(voter);

        // Check that the locked balance is larger than the old votum.
        if (lockedBalance /* TODO OPT */ <= oldVotum) {
            revert InsufficientLockedBalance({ sender: voter, lockedBalance: lockedBalance });
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

        // Eventually update the most voted implementation
        {
            XanStorage storage $ = _getXanStorage();
            address currentImpl = implementation();
            address mostVotedImpl = mostVotedImplementation();

            uint256 mostTotalVotes = $._voteData[currentImpl][mostVotedImpl].totalVotes;

            // Update the most voted implementation.
            if (_voteData.totalVotes > mostTotalVotes) {
                _setMostVotedImplementation(newImplementation);
            }
        }

        emit VoteCast({ voter: voter, newImplementation: newImplementation, value: delta });
    }

    /// @inheritdoc IXan
    function revokeVote(address newImplementation) external override {
        address voter = msg.sender;
        VoteData storage _voteData = _getVoteData(newImplementation);

        // Cache the old votum of the voter.
        uint256 oldVotum = _voteData.vota[voter];

        // Set the votum of the voter to zero.
        _voteData.vota[voter] = 0;

        // Revoke the old votum by subtracting it from the total votes.
        _voteData.totalVotes -= oldVotum;

        // TODO how to determine the most voted impl. ?

        emit VoteRevoked({ voter: voter, newImplementation: newImplementation, value: oldVotum });
    }

    /// @inheritdoc IXan
    function startDelayPeriod(address newImplementation) external override {
        // Check that all upgrade criteria are met befor
        checkUpgradeCriteria(newImplementation);

        VoteData storage _voteData = _getVoteData(newImplementation);

        uint48 startTime = Time.timestamp();

        if (_voteData.delayEndTime != 0) {
            revert DelayPeriodNotStarted(newImplementation);
        }

        _voteData.delayEndTime = startTime + DELAY_DURATION;

        emit DelayStarted({ newImplementation: newImplementation, startTime: startTime, endTime: _voteData.delayEndTime });
    }

    /// @inheritdoc IXan
    function totalVotes(address newImplementation) external view override returns (uint256 votes) {
        votes = _getXanStorage()._voteData[implementation()][newImplementation].totalVotes;
    }

    /// @notice @inheritdoc IXan
    // slither-disable-next-line dead-code
    function lockedTotalSupply() external view override returns (uint256 lockedSupply) {
        lockedSupply = _getXanStorage()._lockedTotalSupply[implementation()];
    }

    function implementation() public view override returns (address currentImplementation) {
        currentImplementation = ERC1967Utils.getImplementation();
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
        if (newImplementation != mostVotedImplementation()) {
            revert ImplementationNotMostVoted({
                newImplementation: newImplementation,
                mostVotedImplementation: mostVotedImplementation()
            });
        }
    }

    /// @notice @inheritdoc IXan
    function checkDelayPeriod(address newImplementation) public view override {
        uint48 delayEndTime = _getVoteData(newImplementation).delayEndTime;

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
        lockedBalance = _getXanStorage()._lockedBalances[implementation()][from];
    }

    /// @notice Returns the most voted implementation.
    /// @return mostVotedNewImplementation The most voted new implementation.
    function mostVotedImplementation() public view override returns (address mostVotedNewImplementation) {
        mostVotedNewImplementation = _getXanStorage()._mostVotedNewImplementation[implementation()];
    }

    /// @notice Sets a new most voted implementation.
    /// @param newMostVotedImplementation The new most voted implementation to set.
    function _setMostVotedImplementation(address newMostVotedImplementation) internal {
        _getXanStorage()._mostVotedNewImplementation[implementation()] = newMostVotedImplementation;
    }

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    // solhint-disable-next-line func-name-mixedcase
    function __Xan_init() internal onlyInitializing {
        __ERC20_init("Anoma", "Xan");
        _mint(msg.sender, 1_000_000_000);
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal override {
        // Allow only unlocked balances to be updated.
        if (from != address(0)) {
            uint256 unlockedBalance = unlockedBalanceOf(from);

            if (value > unlockedBalance) {
                revert InsufficientUnlockedBalance({ sender: from, unlockedBalance: unlockedBalance, needed: value });
            }
        }

        super._update(from, to, value);
    }

    /// @notice Checks if the quorum is reached for a new implementation.
    /// @param newImplementation The new implementation to check.
    /// @return reached Whether quorum for the new implementation is reached.
    function _isQuorumReached(address newImplementation) internal view returns (bool reached) {
        uint256 total = _getVoteData(newImplementation).totalVotes;

        reached = total > totalSupply() / uint256(2);
    }

    /// @notice Authorizes an upgrade.
    /// @param newImplementation The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImplementation) internal view override {
        checkDelayPeriod(newImplementation);

        checkUpgradeCriteria(newImplementation);
    }

    /// @notice Returns the vote data for a new implementation.
    /// @param newImplementation The new implementation to get the vote storage for.
    /// @return voteData The vote data.
    function _getVoteData(address newImplementation) private view returns (VoteData storage voteData) {
        voteData = _getXanStorage()._voteData[implementation()][newImplementation];
    }

    /// @notice Returns the storage from the contract storage location.
    /// @return $ The storage.
    function _getXanStorage() private pure returns (XanStorage storage $) {
        // solhint-disable no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            $.slot := _XAN_STORAGE_LOCATION
        }
        // solhint-enable no-inline-assembly
    }
}
