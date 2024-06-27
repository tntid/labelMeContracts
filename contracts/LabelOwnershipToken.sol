// SPDX-License-Identifier: MIT
// LabelOwnershipToken.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LabelOwnershipToken is ERC721, Ownable {
    uint256 private _tokenIdCounter = 1;

    constructor(address initialOwner) ERC721("Label Ownership Token", "LOT") Ownable(initialOwner) {}

    function mint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(to, tokenId);
        return tokenId;
    }
}