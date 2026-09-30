// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IXanV2} from "./interfaces/IXanV2.sol";
import {IXanVesting} from "./interfaces/IXanVesting.sol";
import {XanV2} from "./XanV2.sol";

/// @title XanVesting
/// @author Anoma Foundation, 2026
/// @notice Vests the XAN principals that the genesis distribution did not contain, with the schedule and the unlock
/// mechanism of `XanV2`, and transfers the unlocked tokens from its own XAN balance.
/// @dev The principal of an account is the sum of its locked balance, which this contract still holds, and its
/// unlocked balance, which this contract has already transferred.
/// @custom:security-contact security@anoma.foundation
contract XanVesting is IXanVesting, Ownable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IXanVesting
    IERC20 public immutable override XAN_TOKEN;

    /// @notice The timestamp at which the linear vesting of the principals starts.
    uint48 private immutable _VESTING_START;

    /// @notice The duration over which the principals vest linearly.
    uint48 private immutable _VESTING_DURATION;

    mapping(address account => uint256 principal) private _principals;

    /// @notice The cumulative amount that each account has unlocked and that this contract transferred to it.
    mapping(address account => uint256 unlockedAmount) private _unlocked;

    uint256 private _totalPrincipal;

    /// @notice The sum of the amounts that all accounts have unlocked.
    uint256 private _totalUnlocked;

    /// @notice The accounts that have a principal, in the order in which they were added.
    address[] private _accounts;

    /// @notice Thrown if the zero address is provided as the XAN token in the constructor.
    error ZeroTokenNotAllowed();

    /// @notice Thrown if the zero address is provided as the account of a recipient.
    error ZeroAccountNotAllowed();

    /// @notice Thrown if this contract is provided as the account of a recipient.
    error SelfRecipientNotAllowed();

    /// @notice Thrown if the zero amount is provided as the principal of a recipient.
    error ZeroPrincipalNotAllowed();

    /// @notice Thrown when a principal is added for an account that already has a principal in this contract.
    error PrincipalAlreadySet(address account, uint256 principal);

    /// @notice Thrown when a principal is added for an account that already has a principal in the XAN token.
    error PrincipalSetInToken(address account, uint256 principal);

    /// @notice Thrown when the XAN balance of this contract is below the amount that the caller unlocks.
    error TokenBalanceInsufficient(uint256 tokenBalance, uint256 value);

    /// @notice Thrown when the owner withdraws more than the XAN that this contract holds above the total locked
    /// balance.
    error SurplusInsufficient(uint256 surplus, uint256 value);

    /// @notice Binds the XAN token, copies its vesting schedule into the bytecode, and adds the initial principals.
    /// @param xanToken The XAN token proxy, which this contract transfers on unlock and reads existing principals and
    /// the vesting schedule from.
    /// @param initialOwner The account that can add more principals and withdraw the surplus.
    /// @param recipients The initial accounts and the principals vesting for them.
    constructor(IERC20 xanToken, address initialOwner, Recipient[] memory recipients) Ownable(initialOwner) {
        require(address(xanToken) != address(0), ZeroTokenNotAllowed());

        uint48 vestingStartTimestamp = IXanV2(address(xanToken)).vestingStart();
        uint48 vestingDuration = IXanV2(address(xanToken)).vestingEnd() - vestingStartTimestamp;

        XAN_TOKEN = xanToken;
        _VESTING_START = vestingStartTimestamp;
        _VESTING_DURATION = vestingDuration;

        emit IXanV2.VestingScheduled({start: vestingStartTimestamp, duration: vestingDuration});

        uint256 count = recipients.length;
        uint256 addedPrincipal = 0;
        for (uint256 i = 0; i < count; ++i) {
            _addRecipient({account: recipients[i].account, principal: recipients[i].principal});
            addedPrincipal += recipients[i].principal;
        }
        _totalPrincipal = addedPrincipal;
    }

    /// @inheritdoc IXanVesting
    function unlock() external override returns (uint256 value) {
        uint256 vested = _vestedAmount(_principals[msg.sender]);
        uint256 alreadyUnlocked = _unlocked[msg.sender];

        // `vested` is monotonically non-decreasing in time and capped at the principal, so it can never drop below
        // `alreadyUnlocked`. Revert instead of emitting a no-op unlock.
        require(vested > alreadyUnlocked, XanV2.NothingToUnlock({account: msg.sender}));

        unchecked {
            // Safe: checked `vested > alreadyUnlocked` above.
            value = vested - alreadyUnlocked;
        }

        uint256 tokenBalance = XAN_TOKEN.balanceOf(address(this));
        require(value < tokenBalance + 1, TokenBalanceInsufficient({tokenBalance: tokenBalance, value: value}));

        _unlocked[msg.sender] = vested;
        _totalUnlocked += value;

        emit IXanV2.Unlocked({account: msg.sender, value: value});

        XAN_TOKEN.safeTransfer(msg.sender, value);
    }

    /// @inheritdoc IXanVesting
    function addRecipients(Recipient[] calldata recipients) external override onlyOwner {
        uint256 count = recipients.length;
        uint256 addedPrincipal = 0;
        for (uint256 i = 0; i < count; ++i) {
            _addRecipient({account: recipients[i].account, principal: recipients[i].principal});
            addedPrincipal += recipients[i].principal;
        }
        // NOTE: The `PrincipalAdded` event of each entry reports its part of this change.
        // slither-disable-next-line events-maths
        _totalPrincipal += addedPrincipal;
    }

    /// @inheritdoc IXanVesting
    function withdraw(address receiver, uint256 value) external override onlyOwner {
        uint256 lockedBalance = totalLockedBalance();
        uint256 tokenBalance = XAN_TOKEN.balanceOf(address(this));
        uint256 surplus = tokenBalance > lockedBalance ? tokenBalance - lockedBalance : 0;

        require(value < surplus + 1, SurplusInsufficient({surplus: surplus, value: value}));

        emit Withdrawn({receiver: receiver, value: value});

        XAN_TOKEN.safeTransfer(receiver, value);
    }

    /// @inheritdoc IXanVesting
    function getRecipients() external view override returns (Recipient[] memory recipients) {
        uint256 count = _accounts.length;
        recipients = new Recipient[](count);
        for (uint256 i = 0; i < count; ++i) {
            address account = _accounts[i];
            recipients[i] = Recipient({account: account, principal: _principals[account]});
        }
    }

    /// @inheritdoc IXanVesting
    function unlockedBalanceOf(address account) public view override returns (uint256 unlockedBalance) {
        unlockedBalance = _unlocked[account];
    }

    /// @inheritdoc IXanVesting
    function lockedBalanceOf(address account) public view override returns (uint256 lockedBalance) {
        // `_unlocked[account] <= _principals[account]` is maintained by `unlock` (capped at the vested amount).
        lockedBalance = _principals[account] - _unlocked[account];
    }

    /// @inheritdoc IXanVesting
    function principalOf(address account) public view override returns (uint256 principal) {
        principal = _principals[account];
    }

    /// @inheritdoc IXanVesting
    function totalPrincipal() public view override returns (uint256 total) {
        total = _totalPrincipal;
    }

    /// @inheritdoc IXanVesting
    function totalLockedBalance() public view override returns (uint256 total) {
        // `_totalUnlocked <= _totalPrincipal` holds because each account unlocks at most its principal.
        total = _totalPrincipal - _totalUnlocked;
    }

    /// @inheritdoc IXanVesting
    function unlockableBalanceOf(address account) public view override returns (uint256 value) {
        uint256 vested = _vestedAmount(_principals[account]);
        uint256 alreadyUnlocked = _unlocked[account];

        value = vested > alreadyUnlocked ? vested - alreadyUnlocked : 0;
    }

    /// @inheritdoc IXanVesting
    function vestingStart() public view override returns (uint48 start) {
        start = _VESTING_START;
    }

    /// @inheritdoc IXanVesting
    function vestingEnd() public view override returns (uint48 end) {
        end = _VESTING_START + _VESTING_DURATION;
    }

    /// @notice Adds the principal of an account that has no principal yet, neither here nor in the XAN token.
    /// @param account The account the principal vests for.
    /// @param principal The amount of XAN vesting for the account.
    /// @dev The caller must add `principal` to `_totalPrincipal`.
    function _addRecipient(address account, uint256 principal) internal {
        require(account != address(0), ZeroAccountNotAllowed());
        require(account != address(this), SelfRecipientNotAllowed());
        require(principal != 0, ZeroPrincipalNotAllowed());

        uint256 existingPrincipal = _principals[account];
        require(existingPrincipal == 0, PrincipalAlreadySet({account: account, principal: existingPrincipal}));

        // NOTE: The XAN token has no batch getter for principals, so the read belongs in the loop.
        // forge-lint: disable-next-line(calls-loop)
        uint256 tokenPrincipal = IXanV2(address(XAN_TOKEN)).principalOf(account);
        require(tokenPrincipal == 0, PrincipalSetInToken({account: account, principal: tokenPrincipal}));

        _principals[account] = principal;
        _accounts.push(account);

        emit PrincipalAdded({account: account, principal: principal});
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
}
