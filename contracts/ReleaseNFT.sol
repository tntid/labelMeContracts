// SPDX-License-Identifier: MIT
// ReleaseNFT.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ReleaseNFT is ERC721Enumerable, Ownable {
    uint256 private _nextTokenId = 1;
    mapping(uint256 => string) private _tokenIPFSHashes;

    constructor(string memory name, string memory symbol, address initialOwner) 
        ERC721(name, symbol) 
        Ownable(initialOwner)
    {}

    function mintRelease(address to, string memory ipfsHash) external onlyOwner returns (uint256) {
        uint256 newTokenId = _nextTokenId++;
        _safeMint(to, newTokenId);
        _tokenIPFSHashes[newTokenId] = ipfsHash;
        return newTokenId;
    }

    function getIPFSHash(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _tokenIPFSHashes[tokenId];
    }
}