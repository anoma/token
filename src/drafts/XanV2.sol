// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Parameters} from "../libs/Parameters.sol";
import {XanV1} from "../XanV1.sol";
import {IXanV2} from "./interfaces/IXanV2.sol";

/// @title XanV2
/// @author Anoma Foundation, 2025
/// @notice A draft of the Anoma (XAN) token contract implementation version 2.
/// This is used to test that `XanV1` can be upgraded to subsequent version.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from XanV1
contract XanV2 is IXanV2, XanV1 {
    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v2
    /// @param forwarder The forwarder being allowed to mint more tokens.
    struct XanV2Storage {
        address forwarder;
    }

    /// @notice The ERC-7201 storage location of the Xan V2 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v2")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V2_STORAGE_LOCATION =
        0x52ac9b9514a24171c0416c0576d612fe5fab9f5a41dcf77ddbf6be60ca9da600;

    /// @notice Limits functions to be callable only by the forwarder address.
    modifier onlyForwarder() {
        _checkForwarder();
        _;
    }

    /// @notice Initializes the XanV2 contract.
    /// @param distributor The distributor address being the initial recipient of the minted tokens and authorized
    /// caller of the `transferAndLock` function.
    /// @param council The address of the governance council contract.
    /// @param xanV2Forwarder The XanV2 forwarder contract.
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2( /* solhint-disable-line comprehensive-interface*/
        address distributor,
        address council,
        address xanV2Forwarder
    ) external reinitializer(2) {
        // Initialize inherited contracts
        __ERC20_init({name_: Parameters.NAME, symbol_: Parameters.SYMBOL});
        __ERC20Permit_init({name: Parameters.NAME});
        __ERC20Burnable_init();
        __UUPSUpgradeable_init();

        // Initialize the XanV1 contract
        _mint(distributor, Parameters.SUPPLY);
        _getCouncilData().council = council;

        // Initialize the XanV2 contract
        _getXanV2Storage().forwarder = xanV2Forwarder;
    }

    /// @notice Reinitializes the XanV2 contract after an upgrade from XanV1.
    /// @param xanV2Forwarder The XanV2 forwarder contract.
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    /// @custom:oz-upgrades-validate-as-initializer
    function reinitializeFromV1(address xanV2Forwarder /* solhint-disable-line comprehensive-interface*/ )
        external
        reinitializer(2)
    {
        // Initialize the XanV2 contract
        _getXanV2Storage().forwarder = xanV2Forwarder;
    }

    /// @inheritdoc IXanV2
    function mint(address account, uint256 value) external override onlyForwarder {
        _mint(account, value);
    }

    /// @inheritdoc IXanV2
    function forwarder() public view override returns (address addr) {
        addr = _getXanV2Storage().forwarder;
    }

    /// @notice Throws if the sender is not the forwarder.
    function _checkForwarder() internal view {
        if (forwarder() != _msgSender()) {
            revert UnauthorizedCaller({caller: _msgSender()});
        }
    }

    /// @notice Returns the storage from the Xan V2 storage location.
    /// @return xanV2Storage The data associated with the Xan V2 token storage.
    function _getXanV2Storage() internal pure returns (XanV2Storage storage xanV2Storage) {
        // solhint-disable no-inline-assembly
        {
            // slither-disable-next-line assembly
            assembly {
                xanV2Storage.slot := _XAN_V2_STORAGE_LOCATION
            }
        }
        // solhint-enable no-inline-assembly
    }
}
