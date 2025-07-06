// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Upgrades, UnsafeUpgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

import {Test} from "forge-std/Test.sol";

import {Parameters} from "../src/libs/Parameters.sol";
import {IXanV1, XanV1} from "../src/XanV1.sol";

contract XanV1UnitTest is Test {
    address internal _defaultSender;
    XanV1 internal _xanProxy;

    function setUp() public {
        (, _defaultSender,) = vm.readCallers();

        _xanProxy = XanV1(
            Upgrades.deployUUPSProxy({
                contractName: "XanV1.sol:XanV1",
                initializerData: abi.encodeCall(XanV1.initializeV1, (_defaultSender, address(uint160(1))))
            })
        );
    }

    function test_permits_spending_given_an_EIP712_signature() public {
        uint256 alicePrivKey = 0xA11CE;
        address aliceAddr = vm.addr(alicePrivKey);
        address spender = address(uint160(2));

        // Give funds to Alice
        vm.prank(_defaultSender);
        _xanProxy.transfer({to: aliceAddr, value: 1_000});

        // Sign message
        uint256 nonce = _xanProxy.nonces(aliceAddr);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 500;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                aliceAddr,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = _xanProxy.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivKey, digest);

        // Check that the spender is allowed to spend 0 XAN of Alice before the `permit` call.
        assertEq(_xanProxy.allowance({owner: aliceAddr, spender: spender}), 0);

        // Given the signature, anyone (here `_defaultSender`) can set the allowance.
        vm.prank(_defaultSender);
        _xanProxy.permit({owner: aliceAddr, spender: spender, value: value, deadline: deadline, v: v, r: r, s: s});

        // Check that the spender is allowed to spend `value` XAN of Alice after the `permit` call.
        assertEq(_xanProxy.allowance({owner: aliceAddr, spender: spender}), value);
    }
}
