// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IApprovedMintERC721} from "./interfaces/IApprovedMintERC721.sol";
import {Roles} from "./Roles.sol";

contract ApprovedMintERC721 is IApprovedMintERC721, ERC721, Roles {
    uint8 internal constant MINT_APPROVER_ROLE = 0x01;

    mapping(address => uint256) private _userNonce;
    uint256 internal _totalSupply;

    constructor(address admin, address mintApprover) ERC721("ThePurpose", "PPS") Roles(admin) {
        _setRole(mintApprover, MINT_APPROVER_ROLE, true);
    }

    /// @notice (Public) Mint the NFT validating the end of a cycle.
    /// @param blockNumber Number of the block when the signature expires
    /// @param signature Signature provided by the API to authorize this ticket sale at given price
    function mint(uint256 blockNumber, bytes calldata signature) external {
        _checkMintSignature(blockNumber, signature);
        _mint(msg.sender, _totalSupply);
        _totalSupply += 1;
    }

    /// @dev Extracts the address of the signer from a hash and a signature
    /// @param message SHA-3 Hash of the signed message
    /// @param signature Signature
    /// @return Address of the signer
    function _getSigner(bytes32 message, bytes calldata signature) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        return ECDSA.recover(hash, signature);
    }

    /// @dev Checks the validity of a signature to allow the mint of an NFT
    /// @param blockNumber Number of the block when the signature expires
    /// @param signature Signature to check
    function _checkMintSignature(uint256 blockNumber, bytes calldata signature) internal view {
        if (blockNumber < block.number) {
            revert ExpiredSignature();
        }
        address signer =
            _getSigner(keccak256(abi.encodePacked(msg.sender, _userNonce[msg.sender], blockNumber)), signature);
        if (!_hasRole(signer, 1)) {
            revert Unauthorized();
        }
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}
