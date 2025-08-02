// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleTest is Test {
    function testOpenZeppelinImport() public {
        // This test just verifies that OpenZeppelin imports work
        assertTrue(true);
    }
} 