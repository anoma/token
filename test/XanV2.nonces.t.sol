// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Test} from "forge-std/Test.sol";

import {XanV2} from "../src/drafts/XanV2.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {XanV1} from "../src/XanV1.sol";
import {MockXanV2} from "./mocks/XanV2.m.sol";

/// @notice Verifies that `permit` (from `ERC20PermitUpgradeable`) and `delegateBySig` (from `ERC20VotesUpgradeable`)
/// draw from a single, shared `NoncesUpgradeable` counter per account, as wired by the `nonces` override.
contract XanV2NoncesTest is Test {
    uint256 internal constant _ALICE_PRIVATE_KEY = 0xA11CE;

    address internal _alice;
    address internal immutable _SPENDER = makeAddr("spender");
    address internal immutable _DELEGATEE = makeAddr("delegatee");
    address internal _defaultSender;
    address internal immutable _GOVERNANCE_COUNCIL = makeAddr("governanceCouncil");
    XanV1 internal _xanV1Proxy;
    XanV2 internal _xanV2Proxy;
    address internal _xanV2Impl;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();
        _alice = vm.addr(_ALICE_PRIVATE_KEY);

        // Deploy proxy and mint tokens for the `_defaultSender`.
        _xanV1Proxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, _GOVERNANCE_COUNCIL))
            })
        );

        // Point the V2 mock at the locally deployed V1 implementation (the vesting principal is stored under it).
        _xanV2Impl = address(
            new MockXanV2(
                _xanV1Proxy.implementation(), msg.sender, Parameters.VESTING_START, Parameters.VESTING_DURATION
            )
        );

        _winUpgradeVoteForV2Impl(_xanV1Proxy);

        skip(Parameters.DELAY_DURATION);

        UnsafeUpgrades.upgradeProxy({
            proxy: address(_xanV1Proxy), newImpl: _xanV2Impl, data: abi.encodeCall(XanV2.reinitializeFromV1, ())
        });

        _xanV2Proxy = XanV2(address(_xanV1Proxy));
    }

    /// @notice A `permit` and a subsequent `delegateBySig` for the same account advance and consume the same nonce
    /// counter: the delegation must use the nonce left behind by the permit.
    function test_permit_and_delegateBySig_share_one_nonce_counter() public {
        uint256 deadline = block.timestamp + 1 hours;

        assertEq(_xanV2Proxy.nonces(_alice), 0);

        // `permit` consumes nonce 0 (its nonce is taken from the shared counter internally).
        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _alice, spender: _SPENDER, value: 500, nonce: 0, deadline: deadline});
        _xanV2Proxy.permit({owner: _alice, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        assertEq(_xanV2Proxy.allowance(_alice, _SPENDER), 500);
        assertEq(_xanV2Proxy.nonces(_alice), 1);

        // `delegateBySig` must now use nonce 1 — the value the permit left in the shared counter.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 1, deadline);
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 1, expiry: deadline, v: dv, r: dr, s: ds});

        assertEq(_xanV2Proxy.delegates(_alice), _DELEGATEE);
        assertEq(_xanV2Proxy.nonces(_alice), 2);
    }

    /// @notice The reverse direction: a `delegateBySig` consumes nonce 0, so a subsequent `permit` must use nonce 1.
    function test_delegateBySig_and_permit_share_one_nonce_counter() public {
        uint256 deadline = block.timestamp + 1 hours;

        // `delegateBySig` consumes nonce 0.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 0, deadline);
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 0, expiry: deadline, v: dv, r: dr, s: ds});

        assertEq(_xanV2Proxy.delegates(_alice), _DELEGATEE);
        assertEq(_xanV2Proxy.nonces(_alice), 1);

        // `permit` must now sign over nonce 1 — the value the delegation left in the shared counter.
        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _alice, spender: _SPENDER, value: 500, nonce: 1, deadline: deadline});
        _xanV2Proxy.permit({owner: _alice, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        assertEq(_xanV2Proxy.allowance(_alice, _SPENDER), 500);
        assertEq(_xanV2Proxy.nonces(_alice), 2);
    }

    /// @notice A nonce already consumed by `permit` cannot be reused by `delegateBySig`, proving the counter is shared
    /// rather than per-extension.
    function test_delegateBySig_cannot_reuse_a_nonce_consumed_by_permit() public {
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _alice, spender: _SPENDER, value: 500, nonce: 0, deadline: deadline});
        _xanV2Proxy.permit({owner: _alice, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        // Sign a delegation over the already-consumed nonce 0; the shared counter now stands at 1.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 0, deadline);
        vm.expectRevert(abi.encodeWithSelector(NoncesUpgradeable.InvalidAccountNonce.selector, _alice, 1));
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 0, expiry: deadline, v: dv, r: dr, s: ds});
    }

    function _winUpgradeVoteForV2Impl(XanV1 xanV1Proxy) internal {
        vm.startPrank(_defaultSender);
        xanV1Proxy.lock(xanV1Proxy.unlockedBalanceOf(_defaultSender));
        xanV1Proxy.castVote(_xanV2Impl);
        xanV1Proxy.scheduleVoterBodyUpgrade();
        vm.stopPrank();
        skip(Parameters.DELAY_DURATION);
    }

    function _signPermit(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _xanV2Proxy.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(_ALICE_PRIVATE_KEY, digest);
    }

    function _signDelegation(address delegatee, uint256 nonce, uint256 expiry)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"), delegatee, nonce, expiry
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _xanV2Proxy.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(_ALICE_PRIVATE_KEY, digest);
    }
}
