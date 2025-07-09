// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IForeignReserveV1} from "./interfaces/IForeignReserveV1.sol";

/// @title ForeignReserveV1
/// @author Anoma Foundation, 2025
/// @notice The interface of the foreign reserve contract, an arbitrary executor owned by the Anoma (XAN) token and
/// receiving fees from the [Anoma token distributor](https://github.com/anoma/token-distributor) contract.
/// @custom:security-contact security@anoma.foundation
contract ForeignReserveV1 is
    IForeignReserveV1,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransientUpgradeable
{
    using Address for address;

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Emits an event if native tokens are received.
    receive() external payable /* solhint-disable-line comprehensive-interface*/ {
        emit NativeTokenReceived(msg.sender, msg.value);
    }

    /// @notice Initializes the contract and sets the owner.
    /// @param initialOwner The initial owner.
    function initializeV1( /* solhint-disable-line comprehensive-interface*/ address initialOwner)
        external
        initializer
    {
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
        override
        onlyOwner
        nonReentrant
        returns (bytes memory result)
    {
        result = target.functionCallWithValue(data, value);
    }

    /// @notice Restricts upgrades to a new implementation to the owner.
    /// @param newImplementation The new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner 
    // solhint-disable-next-line no-empty-blocks
    {}
}
