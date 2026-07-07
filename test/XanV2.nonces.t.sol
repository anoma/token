// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";

import {XanV2Fixture} from "./fixtures/XanV2Fixture.sol";

/// @notice Verifies that `permit` (from `ERC20PermitUpgradeable`) and `delegateBySig` (from `ERC20VotesUpgradeable`)
/// draw from a single, shared `NoncesUpgradeable` counter per account, as wired by the `nonces` override.
contract XanV2NoncesTest is XanV2Fixture {
    uint256 internal constant _ALICE_PRIVATE_KEY = 0xA11CE;
    address internal immutable _ALICE = vm.addr(_ALICE_PRIVATE_KEY);
    address internal immutable _SPENDER = makeAddr("spender");
    address internal immutable _DELEGATEE = makeAddr("delegatee");

    function test_nonces_of_permit_do_not_conflict_with_nonces_of_delegateBySig() public {
        uint256 deadline = block.timestamp + 1 hours;

        assertEq(_xanV2Proxy.nonces(_ALICE), 0);

        // `permit` consumes nonce 0 (its nonce is taken from the shared counter internally).
        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _ALICE, spender: _SPENDER, value: 500, nonce: 0, deadline: deadline});
        _xanV2Proxy.permit({owner: _ALICE, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        assertEq(_xanV2Proxy.allowance(_ALICE, _SPENDER), 500);
        assertEq(_xanV2Proxy.nonces(_ALICE), 1);

        // `delegateBySig` must now use nonce 1 — the value the permit left in the shared counter.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 1, deadline);
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 1, expiry: deadline, v: dv, r: dr, s: ds});

        assertEq(_xanV2Proxy.delegates(_ALICE), _DELEGATEE);
        assertEq(_xanV2Proxy.nonces(_ALICE), 2);
    }

    function test_nonces_of_delegateBySig_do_not_conflict_with_nonces_of_permit() public {
        uint256 deadline = block.timestamp + 1 hours;

        // `delegateBySig` consumes nonce 0.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 0, deadline);
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 0, expiry: deadline, v: dv, r: dr, s: ds});

        assertEq(_xanV2Proxy.delegates(_ALICE), _DELEGATEE);
        assertEq(_xanV2Proxy.nonces(_ALICE), 1);

        // `permit` must now sign over nonce 1 — the value the delegation left in the shared counter.
        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _ALICE, spender: _SPENDER, value: 500, nonce: 1, deadline: deadline});
        _xanV2Proxy.permit({owner: _ALICE, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        assertEq(_xanV2Proxy.allowance(_ALICE, _SPENDER), 500);
        assertEq(_xanV2Proxy.nonces(_ALICE), 2);
    }

    /// @notice A nonce already consumed by `permit` cannot be reused by `delegateBySig`, proving the counter is shared
    /// rather than per-extension.
    function test_nonces_cannot_be_reused_across_signature_types() public {
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 pv, bytes32 pr, bytes32 ps) =
            _signPermit({owner: _ALICE, spender: _SPENDER, value: 500, nonce: 0, deadline: deadline});
        _xanV2Proxy.permit({owner: _ALICE, spender: _SPENDER, value: 500, deadline: deadline, v: pv, r: pr, s: ps});

        // Sign a delegation over the already-consumed nonce 0; the shared counter now stands at 1.
        (uint8 dv, bytes32 dr, bytes32 ds) = _signDelegation(_DELEGATEE, 0, deadline);
        vm.expectRevert(
            abi.encodeWithSelector(NoncesUpgradeable.InvalidAccountNonce.selector, _ALICE, 1), address(_xanV2Proxy)
        );
        _xanV2Proxy.delegateBySig({delegatee: _DELEGATEE, nonce: 0, expiry: deadline, v: dv, r: dr, s: ds});
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
