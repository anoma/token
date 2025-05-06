// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

contract MockPersons {
    string[16] internal _names = [
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

    address[16] internal _addresses;
    mapping(string name => address person) internal _persons;
    mapping(string name => uint256 personId) internal _personIds;

    constructor() {
        for (uint256 i = 0; i < _names.length; ++i) {
            _addresses[i] = address(uint160(i + 1));
            _persons[_names[i]] = _addresses[i];
            _personIds[_names[i]] = i;
        }
    }

    function person(string memory name) internal view returns (address addr) {
        addr = _persons[name];
    }

    function person(uint256 id) internal view returns (address addr) {
        addr = _addresses[id];
    }

    function personId(string memory name) internal view returns (uint256 id) {
        id = _personIds[name];
    }

    function personAddrAndId(string memory name) internal view returns (address addr, uint256 id) {
        addr = person(name);
        id = personId(name);
    }
}
