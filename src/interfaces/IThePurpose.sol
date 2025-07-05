// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IThePurpose is IERC721 {
    function totalSupply() external view returns (uint256);
}
