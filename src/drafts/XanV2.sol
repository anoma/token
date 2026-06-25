// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {Council} from "../libs/Council.sol";
import {Locking} from "../libs/Locking.sol";
import {Voting} from "../libs/Voting.sol";
import {IXanV2} from "./interfaces/IXanV2.sol";

/// @title XanV2
/// @author Anoma Foundation, 2026
/// @notice The Anoma (XAN) token contract implementation version 2.
/// @dev The V2 upgrade
/// * removes the V1 built-in governance and replaces it with simple ownership
/// * adds a linear vesting mechanism unlocking locked tokens
/// * adds ERC-20 vote delegation and checkpoints (`ERC20Votes`)
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from XanV1
contract XanV2 is
    IXanV2,
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @notice A struct containing data associated with the V1 implementation.
    /// @dev Kept identical to `XanV1` so that the inherited V1 storage layout is read correctly. Only `lockingData`
    /// is read by V2; `votingData` and `councilData` are retained solely for layout compatibility.
    /// @param lockingData The state associated with the locking mechanism of the V1 implementation.
    /// @param votingData  The state associated with the (now-defunct) V1 voting mechanism.
    /// @param councilData The state associated with the (now-defunct) V1 governance council.
    struct ImplementationData {
        Locking.Data lockingData;
        Voting.Data votingData;
        Council.Data councilData;
    }

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the V1 contract.
    /// @custom:storage-location erc7201:anoma.storage.Xan.v1
    struct XanV1Storage {
        mapping(address currentProxyImplementation => ImplementationData) implementationSpecificData;
    }

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the V2 contract.
    /// @param unlocked The cumulative amount each account has already unlocked (moved from locked to spendable).
    /// @custom:storage-location erc7201:anoma.storage.Xan.v2
    struct XanV2Storage {
        mapping(address owner => uint256) unlocked;
    }

    /// @notice The address of the single mainnet V1 implementation under which the locked balances
    /// (the vesting principal) are stored in the inherited V1 storage.
    address internal constant _XAN_V1_IMPLEMENTATION = 0x03997b568FE70E91A53c458DC19dc29e0bC2735E;

    /// @notice The ERC-7201 storage location of the Xan V1 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v1")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V1_STORAGE_LOCATION =
        0x52f7d5fb153315ca313a5634db151fa7e0b41cd83fe6719e93ed3cd02b69d200;

    /// @notice The owner who can upgrade the proxy.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _OWNER;

    /// @notice The timestamp at which the linear vesting of the formerly locked balances starts.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint48 private immutable _VESTING_START;

    /// @notice The duration over which the formerly locked balances vest linearly.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint48 private immutable _VESTING_DURATION;

    /// @notice The ERC-7201 storage location of the Xan V2 contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.Xan.v2")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V2_STORAGE_LOCATION =
        0x52ac9b9514a24171c0416c0576d612fe5fab9f5a41dcf77ddbf6be60ca9da600;

    /// @notice Thrown when an account tries to move more than its unlocked (spendable) balance.
    error UnlockedBalanceInsufficient(address sender, uint256 unlockedBalance, uint256 valueToLock);

    /// @notice Thrown when `unlock` is called but no tokens have vested since the last unlock.
    error NothingToUnlock(address account);

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized,
    /// and binds the owner and vesting schedule into the implementation bytecode.
    /// @param owner The owner to install on the proxy after the upgrade (e.g. a multisig or DAO).
    /// @param vestingStartTimestamp The timestamp at which the linear vesting of the formerly locked balances starts.
    /// @param vestingDuration The duration over which the formerly locked balances vest linearly.
    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(address owner, uint48 vestingStartTimestamp, uint48 vestingDuration) {
        _OWNER = owner;
        _VESTING_START = vestingStartTimestamp;
        _VESTING_DURATION = vestingDuration;
        _disableInitializers();
    }

    /// @notice Reinitializes the contract after the upgrade from V1, installing the owner and scheduling vesting.
    /// @custom:oz-upgrades-validate-as-initializer
    /// @custom:oz-upgrades-unsafe-allow incorrect-initializer-order
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    function reinitializeFromV1() external reinitializer(2) /* solhint-disable-line comprehensive-interface */  {
        __ERC20Votes_init();
        __Ownable_init({initialOwner: _OWNER});

        emit VestingScheduled({start: _VESTING_START, duration: _VESTING_DURATION});
    }

    /// @inheritdoc IXanV2
    function unlock() external override returns (uint256 value) {
        XanV2Storage storage xanV2Storage = _getXanV2Storage();

        uint256 principal = _principalOf(msg.sender);
        uint256 vested = _vestedAmount(principal);
        uint256 alreadyUnlocked = xanV2Storage.unlocked[msg.sender];

        // `vested` is monotonically non-decreasing in time and capped at `principal`, so it can never drop below
        // `alreadyUnlocked`. Revert instead of emitting a no-op unlock.
        if (vested < alreadyUnlocked + 1) {
            revert NothingToUnlock({account: msg.sender});
        }

        unchecked {
            // Safe: checked `vested > alreadyUnlocked` above.
            value = vested - alreadyUnlocked;
        }

        xanV2Storage.unlocked[msg.sender] = vested;

        emit Unlocked({account: msg.sender, value: value});
    }

    /// @inheritdoc IXanV2
    function implementation() external view override returns (address thisImplementation) {
        thisImplementation = ERC1967Utils.getImplementation();
    }

    /// @inheritdoc IXanV2
    function unlockedBalanceOf(address from) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = balanceOf(from) - lockedBalanceOf(from);
    }

    /// @inheritdoc IXanV2
    function lockedBalanceOf(address from) public view override returns (uint256 lockedBalance) {
        // The still-locked balance is the V1 principal minus what the account has already unlocked.
        // `unlocked[from] <= principal` is maintained by `unlock` (capped at `_vestedAmount(principal) <= principal`).
        lockedBalance = _principalOf(from) - _getXanV2Storage().unlocked[from];
    }

    /// @notice Returns the next unused nonce for an address.
    /// @param owner The address to query the nonce for.
    /// @return nonce The next unused nonce.
    /// @dev Nonces will be used for both, `permit` (`ERC20PermitUpgradeable`) and `delegateBySig`
    /// (`ERC20VotesUpgradeable`) signatures, both of which extend `NoncesUpgradeable`.
    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256 nonce)
    {
        nonce = super.nonces(owner);
    }

    /// @inheritdoc IXanV2
    function claimableBalanceOf(address account) public view override returns (uint256 value) {
        uint256 principal = _principalOf(account);
        uint256 vested = _vestedAmount(principal);
        uint256 alreadyUnlocked = _getXanV2Storage().unlocked[account];

        value = vested > alreadyUnlocked ? vested - alreadyUnlocked : 0;
    }

    /// @inheritdoc IXanV2
    function vestingStart() public view override returns (uint48 start) {
        start = _VESTING_START;
    }

    /// @inheritdoc IXanV2
    function vestingEnd() public view override returns (uint48 end) {
        end = _VESTING_START + _VESTING_DURATION;
    }

    /// @notice Updates the balances. Only the unlocked token balances can be moved, except for the minting case,
    /// where `from == address(0)`.
    /// @param from The address to take the tokens from.
    /// @param to The address to give the tokens to.
    /// @param value The amount of tokens to update that must be unlocked.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        // Require the unlocked balance to be at least the updated value, except for the minting case,
        // where `from == address(0)`.
        // In this case, tokens are created ex-nihilo and formally sent from `address(0)` to the `to` address
        // without balance checks.
        if (from != address(0)) {
            uint256 unlockedBalance = unlockedBalanceOf(from);

            if (value > unlockedBalance) {
                revert UnlockedBalanceInsufficient({ // force linebreak
                    sender: from,
                    unlockedBalance: unlockedBalance,
                    valueToLock: value
                });
            }
        }

        super._update({from: from, to: to, value: value});
    }

    /// @notice Authorizes an upgrade. Restricted to the owner (e.g. a multisig or DAO).
    /// @param newImpl The new implementation to authorize the upgrade to.
    function _authorizeUpgrade(address newImpl) internal view override onlyOwner {
        (newImpl);
    }

    /// @notice Returns the amount of an account's V1 principal that has vested by the current timestamp.
    /// @param principal The account's formerly locked V1 balance.
    /// @return vested The vested amount, linearly interpolated and capped at `principal`.
    function _vestedAmount(uint256 principal) internal view returns (uint256 vested) {
        uint48 start = _VESTING_START;
        uint48 nowTs = Time.timestamp();

        if (nowTs < start + 1) {
            return vested = 0;
        }

        uint48 elapsed = nowTs - start;
        if (elapsed > _VESTING_DURATION - 1) {
            return vested = principal;
        }

        vested = (principal * elapsed) / _VESTING_DURATION;
    }

    /// @notice Returns the formerly locked V1 balance of an account that is the principal subject to vesting.
    /// @param account The account to query.
    /// @return principal The V1 locked balance of the account.
    function _principalOf(address account) internal view returns (uint256 principal) {
        principal =
            _getXanV1Storage().implementationSpecificData[_implementationV1()].lockingData.lockedBalances[account];
    }

    /// @notice Returns the V1 implementation address under which the vesting principal is stored.
    /// @dev Declared `virtual` so tests can point at a locally deployed V1 implementation; in production it is the
    /// single mainnet V1 implementation.
    /// @return implementationV1 The V1 implementation address.
    function _implementationV1() internal view virtual returns (address implementationV1) {
        implementationV1 = _XAN_V1_IMPLEMENTATION;
    }

    /// @notice Returns the storage from the Xan V1 storage location.
    /// @return xanV1Storage The data associated with the Xan V1 token storage.
    function _getXanV1Storage() internal pure returns (XanV1Storage storage xanV1Storage) {
        // solhint-disable no-inline-assembly

        // slither-disable-next-line assembly
        assembly {
            xanV1Storage.slot := _XAN_V1_STORAGE_LOCATION
        }

        // solhint-enable no-inline-assembly
    }

    /// @notice Returns the storage from the Xan V2 storage location.
    /// @return xanV2Storage The data associated with the Xan V2 token storage.
    function _getXanV2Storage() internal pure returns (XanV2Storage storage xanV2Storage) {
        // solhint-disable no-inline-assembly

        // slither-disable-next-line assembly
        assembly {
            xanV2Storage.slot := _XAN_V2_STORAGE_LOCATION
        }

        // solhint-enable no-inline-assembly
    }
}
