// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import {IForwarder, ForwarderBase} from "@anoma/evm-protocol-adapter/ForwarderBase.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {XanV1} from "../../src/XanV1.sol";

contract XanV2Forwarder is ForwarderBase {
    XanV2 internal immutable _XAN_PROXY;

    mapping(address caller => uint48) internal lastMintTimes;

    event XanMinted(address caller, uint256 value);

    error InvalidFunctionSelector(bytes4 expected, bytes4 actual);
    error MintDelayNotPassed(address caller, uint48 lastMintTime, uint48 nextMintTime);

    constructor(XanV2 xanProxy, address protocolAdapter, bytes32 calldataCarrierLogicRef)
        ForwarderBase(protocolAdapter, calldataCarrierLogicRef)
    {
        _XAN_PROXY = xanProxy;
    }

    function _forwardCall(bytes calldata input) internal override returns (bytes memory output) {
        (bytes4 selector, address caller, uint256 value) = abi.decode(input, (bytes4, address, uint256));

        // Check that that the mint function is the call target.
        if (selector != XanV2.mint.selector) {
            revert InvalidFunctionSelector({expected: XanV2.mint.selector, actual: selector});
        }

        uint48 currentTime = Time.timestamp();
        uint48 lastMintTime = lastMintTimes[caller];

        if (currentTime < lastMintTime + 1 days) {
            revert MintDelayNotPassed({caller: caller, lastMintTime: lastMintTime, nextMintTime: lastMintTime + 1 days});
        }
        lastMintTimes[caller] = currentTime;

        emit XanMinted({caller: caller, value: value});

        output = bytes("");

        _XAN_PROXY.mint({account: address(this), value: value});
    }
}

/// @custom:oz-upgrades-from XanV1
contract XanV2 is ContextUpgradeable, XanV1 {
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
    function initialize(address mintRecipient, address protocolAdapter, bytes32 calldataCarrierLogicRef)
        external
        reinitializer(2)
    {
        __XanV1_init(mintRecipient);
        __XanV2_init({protocolAdapter: protocolAdapter, calldataCarrierLogicRef: calldataCarrierLogicRef});
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2(address protocolAdapter, bytes32 calldataCarrierLogicRef) external reinitializer(2) {
        //__XanV2_init({protocolAdapter: protocolAdapter, calldataCarrierLogicRef: calldataCarrierLogicRef});
    }

    /// @notice Mints tokens for
    /// @dev The caller must be the owner.
    function mint(address account, uint256 value) external onlyOwner {
        _mint(account, value);
    }

    /// @notice Returns the address of the owner.
    function owner() public view virtual returns (address ownerAddr) {
        XanV2Storage storage $ = _getXanV2Storage();
        ownerAddr = $.owner;
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function __XanV2_init(address protocolAdapter, bytes32 calldataCarrierLogicRef) internal onlyInitializing {
        __XanV2_init_unchained({protocolAdapter: protocolAdapter, calldataCarrierLogicRef: calldataCarrierLogicRef});
    }

    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function __XanV2_init_unchained(address protocolAdapter, bytes32 calldataCarrierLogicRef)
        internal
        onlyInitializing
    {
        _getXanV2Storage().owner = address(
            new XanV2Forwarder({
                xanProxy: XanV2(address(this)),
                protocolAdapter: protocolAdapter,
                calldataCarrierLogicRef: calldataCarrierLogicRef
            })
        );
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
