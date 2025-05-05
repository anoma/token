// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {IXanV2} from "../interfaces/IXanV2.sol";
import {XanV1} from "../XanV1.sol";

/// @notice A draft of the second version of the XAN contract.
/// This is to ensure that `XanV1` can be upgraded to an subsequent version.
/// @custom:oz-upgrades-from XanV1
contract XanV2 is IXanV2, XanV1 {
    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v2
    /// @param proposedUpgrades The upgrade proposed from a current implementation.
    struct XanV2Storage {
        address owner;
    }

    /// @notice The ERC-7201 storage location of the Xan V2 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v2")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V2_STORAGE_LOCATION =
        0x52ac9b9514a24171c0416c0576d612fe5fab9f5a41dcf77ddbf6be60ca9da600;

    error OwnableUnauthorizedAccount(address account);

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @custom:oz-upgrades-validate-as-initializer
    // solhint-disable-next-line comprehensive-interface
    function initialize(address mintRecipient, address xanV2Forwarder) external reinitializer(2) {
        __XanV1_init({mintRecipient: mintRecipient});
        __XanV2_init({xanV2Forwarder: xanV2Forwarder});
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    /// @custom:oz-upgrades-validate-as-initializer
    // solhint-disable-next-line comprehensive-interface
    function initializeV2(address xanV2Forwarder) external reinitializer(2) {
        __XanV2_init({xanV2Forwarder: xanV2Forwarder});
    }

    /// @inheritdoc IXanV2
    function mint(address account, uint256 value) external override onlyOwner {
        _mint(account, value);
    }

    /// @inheritdoc IXanV2
    function owner() public view virtual override returns (address addr) {
        addr = _getXanV2Storage().owner;
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    // solhint-disable-next-line func-name-mixedcase
    function __XanV2_init(address xanV2Forwarder) internal onlyInitializing {
        __XanV2_init_unchained({xanV2Forwarder: xanV2Forwarder});
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    // solhint-disable-next-line func-name-mixedcase
    function __XanV2_init_unchained(address xanV2Forwarder) internal onlyInitializing {
        _getXanV2Storage().owner = xanV2Forwarder;
    }

    /// @notice Throws if the sender is not the owner.
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /// @notice Returns the storage from the Xan V2 storage location.
    /// @return $ The data associated with Xan token storage.
    function _getXanV2Storage() internal pure returns (XanV2Storage storage $) {
        // solhint-disable no-inline-assembly
        {
            // slither-disable-next-line assembly
            assembly {
                $.slot := _XAN_V2_STORAGE_LOCATION
            }
        }
        // solhint-enable no-inline-assembly
    }
}
