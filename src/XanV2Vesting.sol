// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanV2} from "./interfaces/IXanV2.sol";
import {IXanV2Vesting} from "./interfaces/IXanV2Vesting.sol";
import {XanV2} from "./XanV2.sol";

/// @title XanV2Vesting
/// @author Anoma Foundation, 2026
/// @notice Vests the XAN principals that the genesis distribution did not contain, with the schedule and the unlock
/// mechanism of `XanV2`, and transfers the unlocked tokens from its own XAN balance.
/// @dev The principal of an account is the sum of its locked balance, which it has not unlocked yet, and its unlocked
/// balance, which this contract has already transferred to it. The owner can upgrade the implementation (UUPS).
/// @custom:security-contact security@anoma.foundation
contract XanV2Vesting is IXanV2Vesting, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the `XanV2Vesting` contract.
    /// @param principals The principal of each account.
    /// @param unlocked The cumulative amount that each account has unlocked and that this contract transferred to it.
    /// @param totalPrincipal The sum of all principals.
    /// @param totalUnlocked The sum of the amounts that all accounts have unlocked.
    /// @param accounts The accounts that have a principal, in the order in which they were added.
    /// @custom:storage-location erc7201:anoma.storage.XanV2Vesting
    struct XanV2VestingStorage {
        mapping(address account => uint256 principal) principals;
        mapping(address account => uint256 unlockedAmount) unlocked;
        uint256 totalPrincipal;
        uint256 totalUnlocked;
        address[] accounts;
    }

    /// @notice The ERC-7201 storage location of `XanV2Vesting` (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("anoma.storage.XanV2Vesting")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _XAN_V2_VESTING_STORAGE_LOCATION =
        0xc0cbef80212dc8a521800339e9aa0021b3184553091fca981937d0a1802a3800;

    /// @inheritdoc IXanV2Vesting
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 public immutable override XAN_TOKEN;

    /// @notice The timestamp at which the linear vesting of the principals starts.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint48 private immutable _VESTING_START;

    /// @notice The duration over which the principals vest linearly.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint48 private immutable _VESTING_DURATION;

    /// @notice Thrown if the zero address is provided as the XAN token in the constructor.
    error ZeroTokenNotAllowed();

    /// @notice Thrown if the zero address is provided as the account of a recipient.
    error ZeroAccountNotAllowed();

    /// @notice Thrown if this contract is provided as the account of a recipient.
    error SelfRecipientNotAllowed();

    /// @notice Thrown if the XAN token is provided as the account of a recipient.
    error TokenRecipientNotAllowed();

    /// @notice Thrown if the zero amount is provided as the principal of a recipient.
    error ZeroPrincipalNotAllowed();

    /// @notice Thrown when a principal is added for an account that already has a principal in this contract.
    error PrincipalAlreadySet(address account, uint256 principal);

    /// @notice Thrown when the XAN balance of this contract is below the amount that the caller unlocks.
    error TokenBalanceInsufficient(uint256 tokenBalance, uint256 value);

    /// @notice Thrown when the owner withdraws more than the XAN that this contract holds above the total locked
    /// balance.
    error SurplusInsufficient(uint256 surplus, uint256 value);

    /// @notice Binds the XAN token, copies its vesting schedule into the implementation bytecode, and disables the
    /// initializers on the implementation.
    /// @param xanToken The XAN token proxy, whose XAN this contract transfers on unlock and whose schedule it copies.
    /// @custom:oz-upgrades-unsafe-allow constructor state-variable-immutable
    constructor(IERC20 xanToken) {
        require(address(xanToken) != address(0), ZeroTokenNotAllowed());

        uint48 vestingStartTimestamp = IXanV2(address(xanToken)).vestingStart();
        uint48 vestingDuration = IXanV2(address(xanToken)).vestingEnd() - vestingStartTimestamp;

        XAN_TOKEN = xanToken;
        _VESTING_START = vestingStartTimestamp;
        _VESTING_DURATION = vestingDuration;

        _disableInitializers();
    }

    /// @notice Initializes the proxy with its owner and the initial principals, and emits the vesting schedule.
    /// @param initialOwner The account that can add more principals, withdraw the surplus, and upgrade this contract.
    /// @param recipients The initial accounts and the principals vesting for them.
    function initialize( /* solhint-disable-line comprehensive-interface*/
        address initialOwner,
        Recipient[] calldata recipients
    )
        external
        initializer
    {
        __Ownable_init({initialOwner: initialOwner});

        emit IXanV2.VestingScheduled({start: _VESTING_START, duration: _VESTING_DURATION});

        _addRecipients(recipients);
    }

    /// @inheritdoc IXanV2Vesting
    function unlock() external override returns (uint256 value) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        uint256 vested = _vestedAmount(xanV2VestingStorage.principals[msg.sender]);
        uint256 alreadyUnlocked = xanV2VestingStorage.unlocked[msg.sender];

        // `vested` is monotonically non-decreasing in time and capped at the principal, so it can never drop below
        // `alreadyUnlocked`. Revert instead of emitting a no-op unlock.
        require(vested > alreadyUnlocked, XanV2.NothingToUnlock({account: msg.sender}));

        unchecked {
            // Safe: checked `vested > alreadyUnlocked` above.
            value = vested - alreadyUnlocked;
        }

        uint256 tokenBalance = XAN_TOKEN.balanceOf(address(this));
        require(value < tokenBalance + 1, TokenBalanceInsufficient({tokenBalance: tokenBalance, value: value}));

        xanV2VestingStorage.unlocked[msg.sender] = vested;
        xanV2VestingStorage.totalUnlocked += value;

        emit IXanV2.Unlocked({account: msg.sender, value: value});

        XAN_TOKEN.safeTransfer(msg.sender, value);
    }

    /// @inheritdoc IXanV2Vesting
    function addRecipients(Recipient[] calldata recipients) external override onlyOwner {
        _addRecipients(recipients);
    }

    /// @inheritdoc IXanV2Vesting
    function withdrawSurplus(address receiver, uint256 value) external override onlyOwner {
        uint256 lockedBalance = totalLockedBalance();
        uint256 tokenBalance = XAN_TOKEN.balanceOf(address(this));
        uint256 surplus = tokenBalance > lockedBalance ? tokenBalance - lockedBalance : 0;

        require(value < surplus + 1, SurplusInsufficient({surplus: surplus, value: value}));

        emit SurplusWithdrawn({receiver: receiver, value: value});

        XAN_TOKEN.safeTransfer(receiver, value);
    }

    /// @inheritdoc IXanV2Vesting
    function getRecipients() external view override returns (Recipient[] memory recipients) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        uint256 count = xanV2VestingStorage.accounts.length;
        recipients = new Recipient[](count);
        for (uint256 i = 0; i < count; ++i) {
            address account = xanV2VestingStorage.accounts[i];
            recipients[i] = Recipient({account: account, principal: xanV2VestingStorage.principals[account]});
        }
    }

    /// @inheritdoc IXanV2Vesting
    function unlockedBalanceOf(address account) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = _getXanV2VestingStorage().unlocked[account];
    }

    /// @inheritdoc IXanV2Vesting
    function lockedBalanceOf(address account) public view override returns (uint256 lockedBalance) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        // `unlocked[account] <= principals[account]` is maintained by `unlock` (capped at the vested amount).
        lockedBalance = xanV2VestingStorage.principals[account] - xanV2VestingStorage.unlocked[account];
    }

    /// @inheritdoc IXanV2Vesting
    function principalOf(address account) public view override returns (uint256 principal) {
        principal = _getXanV2VestingStorage().principals[account];
    }

    /// @inheritdoc IXanV2Vesting
    function totalPrincipal() public view override returns (uint256 total) {
        total = _getXanV2VestingStorage().totalPrincipal;
    }

    /// @inheritdoc IXanV2Vesting
    function totalLockedBalance() public view override returns (uint256 total) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        // `totalUnlocked <= totalPrincipal` holds because each account unlocks at most its principal.
        total = xanV2VestingStorage.totalPrincipal - xanV2VestingStorage.totalUnlocked;
    }

    /// @inheritdoc IXanV2Vesting
    function totalUnlockableBalance() public view override returns (uint256 total) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        // `_vestedAmount(totalPrincipal)` is at least the sum of the vested amounts, so at least `totalUnlocked`.
        total = _vestedAmount(xanV2VestingStorage.totalPrincipal) - xanV2VestingStorage.totalUnlocked;
    }

    /// @inheritdoc IXanV2Vesting
    function unlockableBalanceOf(address account) public view override returns (uint256 value) {
        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        uint256 vested = _vestedAmount(xanV2VestingStorage.principals[account]);
        uint256 alreadyUnlocked = xanV2VestingStorage.unlocked[account];

        value = vested > alreadyUnlocked ? vested - alreadyUnlocked : 0;
    }

    /// @inheritdoc IXanV2Vesting
    function vestingStart() public view override returns (uint48 start) {
        start = _VESTING_START;
    }

    /// @inheritdoc IXanV2Vesting
    function vestingEnd() public view override returns (uint48 end) {
        end = _VESTING_START + _VESTING_DURATION;
    }

    /// @notice Adds the principals of accounts that have no principal here yet.
    /// @param recipients The accounts and the principals vesting for them.
    function _addRecipients(Recipient[] calldata recipients) internal {
        uint256 count = recipients.length;
        uint256 addedPrincipal = 0;
        for (uint256 i = 0; i < count; ++i) {
            _addRecipient({account: recipients[i].account, principal: recipients[i].principal});
            addedPrincipal += recipients[i].principal;
        }
        // NOTE: The `PrincipalAdded` event of each entry reports its part of this change.
        // slither-disable-next-line events-maths
        _getXanV2VestingStorage().totalPrincipal += addedPrincipal;
    }

    /// @notice Adds the principal of an account that has no principal here yet.
    /// @param account The account the principal vests for.
    /// @param principal The amount of XAN vesting for the account.
    /// @dev The caller must add `principal` to `totalPrincipal`.
    function _addRecipient(address account, uint256 principal) internal {
        require(account != address(0), ZeroAccountNotAllowed());
        require(account != address(this), SelfRecipientNotAllowed());
        require(account != address(XAN_TOKEN), TokenRecipientNotAllowed());
        require(principal != 0, ZeroPrincipalNotAllowed());

        XanV2VestingStorage storage xanV2VestingStorage = _getXanV2VestingStorage();

        uint256 existingPrincipal = xanV2VestingStorage.principals[account];
        require(existingPrincipal == 0, PrincipalAlreadySet({account: account, principal: existingPrincipal}));

        xanV2VestingStorage.principals[account] = principal;
        xanV2VestingStorage.accounts.push(account);

        emit PrincipalAdded({account: account, principal: principal});
    }

    /// @notice Authorizes an upgrade. Restricted to the owner.
    function _authorizeUpgrade(address) internal view override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @notice Returns the amount of a principal that has vested by the current timestamp.
    /// @param principal The principal of an account.
    /// @return vested The vested amount, linearly interpolated and capped at `principal`.
    function _vestedAmount(uint256 principal) internal view returns (uint256 vested) {
        uint48 startTime = _VESTING_START;
        uint48 currentTime = Time.timestamp();

        if (currentTime < startTime + 1) {
            return vested = 0;
        }

        uint48 elapsedTime = currentTime - startTime;
        if (elapsedTime > _VESTING_DURATION - 1) {
            return vested = principal;
        }

        // The product overflows, and reverts, only for a principal far above the XAN supply.
        vested = (principal * elapsedTime) / _VESTING_DURATION;
    }

    /// @notice Returns the storage from the `XanV2Vesting` storage location.
    /// @return xanV2VestingStorage The data associated with the `XanV2Vesting` storage.
    function _getXanV2VestingStorage() internal pure returns (XanV2VestingStorage storage xanV2VestingStorage) {
        // solhint-disable no-inline-assembly

        // slither-disable-next-line assembly
        assembly {
            xanV2VestingStorage.slot := _XAN_V2_VESTING_STORAGE_LOCATION
        }

        // solhint-enable no-inline-assembly
    }
}
