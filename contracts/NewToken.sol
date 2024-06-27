// SPDX-License-Identifier: MIT
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