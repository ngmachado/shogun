// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { TokenResources } from "./../src/tokens/TokenResources.sol";

contract TokenResourcesTest is Test {

    TokenResources public tokenResources;
    address public owner = address(0x01);

    function setUp() public virtual {
        vm.startPrank(owner);
        tokenResources = new TokenResources();
    }


    // test if owner get the right amount of stones
    function testBalances() public {
        for(uint256 i = 0; i < 5; i++) {
            uint256 balance = tokenResources.balanceOf(owner, i);
            assertEq(balance, 1000000 ether, "wrong balance");
        }
    }

}
