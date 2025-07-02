// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ForeignReserve is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardTransientUpgradeable {
    using Address for address;

    event Received(address sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and sets the owner
    /// @param initialOwner The initial owner.
    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();
    }

    /// @notice Executes arbitrary calls without reentrancy and if called by the owner.
    /// @param target The address to call
    /// @param value ETH to send with the call
    /// @param data Calldata to send
    /// @return result The raw result returned from the call
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        onlyOwner
        nonReentrant
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /// @notice Restricts upgrades to a new implementation to the owner.
    /// @param newImplementation The new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Emits an event if native tokens are deposited.
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
