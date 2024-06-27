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
        require(_exists(tokenId), "Token does not exist");
        return _tokenIPFSHashes[tokenId];
    }
}

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

// NewToken.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NewToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 totalSupply, address owner) 
        ERC20(name, symbol)
    {
        _mint(owner, totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
}