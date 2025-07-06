// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {XanV1} from "../src/XanV1.sol";

contract XanV1PermitTest is Test {
    uint256 internal constant _ALICE_PRIVATE_KEY = 0xA11CE;
    address internal immutable _ALICE = 0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7; // `vm.addr(_ALICE_PRIVATE_KEY)`
    address internal constant _BOB = address(uint160(2));
    address internal constant _CAROL = address(uint160(3));

    XanV1 internal _xanProxy;

    function setUp() public {
        vm.prank(_ALICE);
        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_ALICE, address(uint160(1))))
            })
        );
    }

    function test_permits_reverts_for_invalid_signature() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 500;

        (uint8 v, bytes32 r, bytes32 s) = (0, 0, 0);
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector, address(_xanProxy));
        _xanProxy.permit({owner: _ALICE, spender: _BOB, value: value, deadline: deadline, v: v, r: r, s: s});
    }

    function test_permits_spending_given_an_EIP712_signature() public {
        // Sign message
        uint256 nonce = _xanProxy.nonces(_ALICE);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 500;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                _ALICE,
                _BOB,
                value,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = _xanProxy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_ALICE_PRIVATE_KEY, digest);

        // Check that the spender is allowed to spend 0 XAN of Alice before the `permit` call.
        assertEq(_xanProxy.allowance({owner: _ALICE, spender: _BOB}), 0);

        // Given the signature, anyone (here `_CAROL`) can set the allowance.
        vm.prank(_CAROL);
        _xanProxy.permit({owner: _ALICE, spender: _BOB, value: value, deadline: deadline, v: v, r: r, s: s});

        // Check that the Bob is allowed to spend `value` XAN of Alice after the `permit` call.
        assertEq(_xanProxy.allowance({owner: _ALICE, spender: _BOB}), value);
    }
}
