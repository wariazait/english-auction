// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20} from "../src/ERC20.sol";
import {Test} from "forge-std/Test.sol";

contract SomeToken is ERC20 {
    constructor() ERC20("SomeToken", "STK") {
        _mint(msg.sender, 1000000);
    }
}

contract ERC20Test is Test {
    SomeToken public token;

    function setUp() public {
        token = new SomeToken();
    }

    function testNotEnoughBalance() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20.InsufficientBalance.selector, 1000000, 1000001));
        token.transfer(address(1), 1000001);
    }

    function testEnoughAllowance() public {
        token.approve(address(1), 500000);
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(ERC20.InsufficientAllowance.selector, 500000, 600000));
        token.transferFrom(address(this), address(2), 600000);
    }

    function testValidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20.InvalidAddress.selector, address(0)));
        token.transfer(address(0), 1000);
    }
}
