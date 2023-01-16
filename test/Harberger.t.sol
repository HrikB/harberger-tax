//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Harberger} from "contracts/Harberger.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HarbergerTest is Test {
    Harberger harberger;
    ERC20 token;

    function setUp() public {
        token = new ERC20("tokenName", "tokenSymbol");
        harberger = new Harberger("name", "symb", token, 10, 100);
    }

    function testBasicMint() external {}
}
