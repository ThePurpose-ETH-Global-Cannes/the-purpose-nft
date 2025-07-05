// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ApprovedMintERC721} from "./ApprovedMintERC721.sol";

contract ThePurpose is ApprovedMintERC721, IERC4906 {
    string private _baseMetadataURI;

    constructor(address mintApprover) ApprovedMintERC721(msg.sender, mintApprover) {}

    function setBaseURI(string calldata uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseMetadataURI = uri;
        emit BatchMetadataUpdate(0, _totalSupply);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseMetadataURI;
    }
}