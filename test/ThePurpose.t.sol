// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ThePurpose} from "../src/ThePurpose.sol";

contract ThePurposeTest is Test {
    ThePurpose public thePurpose;
    address public mintApprover = makeAddr("mintApprover");

    function setUp() public {
        thePurpose = new ThePurpose(mintApprover);
    }

    function test_initialState() public view {
        assertEq(thePurpose.totalSupply(), 0);
        assertEq(thePurpose.name(), "ThePurpose");
        assertEq(thePurpose.symbol(), "PPS");
    }
}
