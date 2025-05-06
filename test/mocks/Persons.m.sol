// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

contract MockPersons {
    string[16] public names = [
        "Alice",
        "Bob",
        "Carol",
        "Dave",
        "Eve",
        "Frank",
        "Grace",
        "Harold",
        "Ivy",
        "Jack",
        "Kathrine",
        "Luis",
        "Mallory",
        "Nick",
        "Olga",
        "Paul"
    ];

    address[16] public addresses;
    mapping(string name => address person) public persons;
    mapping(string name => uint256 personId) public personIds;

    constructor() {
        for (uint256 i = 0; i < names.length; ++i) {
            addresses[i] = address(uint160(i + 1));
            persons[names[i]] = addresses[i];
            personIds[names[i]] = i;
        }
    }

    function person(string memory name) public view returns (address addr) {
        addr = persons[name];
    }

    function person(uint256 id) public view returns (address addr) {
        addr = addresses[id];
    }

    function personId(string memory name) public view returns (uint256 id) {
        id = personIds[name];
    }

    function personAddrAndId(string memory name) public view returns (address addr, uint256 id) {
        addr = person(name);
        id = personId(name);
    }
}
