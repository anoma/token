// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IXanV2} from "../interfaces/IXanV2.sol";
import {Parameters} from "../libs/Parameters.sol";
import {XanV1} from "../XanV1.sol";

/// @notice A draft of the second version of the XAN contract.
/// This is to ensure that `XanV1` can be upgraded to an subsequent version.
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

    error UnauthorizedCaller(address caller);

    modifier onlyForwarder() {
        _checkForwarder();
        _;
    }

    /// @notice Initializes the proxy.
    /// @param initialMintRecipient The initial recipient of the minted tokens.
    /// @param xanV2Forwarder The XanV2 forwarder contract.
    /// @custom:oz-upgrades-validate-as-initializer
    // solhint-disable-next-line comprehensive-interface
    function initialize(address initialMintRecipient, address xanV2Forwarder) external reinitializer(2) {
        __XanV1_init({initialMintRecipient: initialMintRecipient});
        __XanV2_init({xanV2Forwarder: xanV2Forwarder});
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    /// @custom:oz-upgrades-validate-as-initializer
    // solhint-disable-next-line comprehensive-interface
    function initializeV2(address xanV2Forwarder) external reinitializer(2) {
        // Initialize the XanV2 contract
        __XanV2_init({xanV2Forwarder: xanV2Forwarder});
    }

    /// @inheritdoc IXanV2
    function mint(address account, uint256 value) external override onlyForwarder {
        _mint(account, value);
    }

    /// @inheritdoc IXanV2
    function forwarder() public view virtual override returns (address addr) {
        addr = _getXanV2Storage().forwarder;
    }

    /// @notice Initializes the XanV2 contract and newly inherited contracts.
    /// @param xanV2Forwarder The XanV2 forwarder contract.
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    // solhint-disable-next-line func-name-mixedcase
    function __XanV2_init(address xanV2Forwarder) internal onlyInitializing {
        __XanV2_init_unchained({xanV2Forwarder: xanV2Forwarder});
    }

    /// @notice Initializes the XanV2 contract.
    /// @param xanV2Forwarder The XanV2 forwarder contract.
    // solhint-disable-next-line func-name-mixedcase
    function __XanV2_init_unchained(address xanV2Forwarder) internal onlyInitializing {
        _getXanV2Storage().forwarder = xanV2Forwarder;
    }

    /// @notice Throws if the sender is not the forwarder.
    function _checkForwarder() internal view virtual {
        if (forwarder() != _msgSender()) {
            revert UnauthorizedCaller({caller: _msgSender()});
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
