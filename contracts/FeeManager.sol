// SPDX-License-Identifier: MIT
// FeeManager.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeManager is Ownable {
    IERC20 public feeToken;
    uint256 public launchFee;
    address public uniswapFactory;
    address public swapTokenAddress;

    event LaunchFeeUpdated(uint256 newFee);
    event SwapTokenAddressUpdated(address newSwapTokenAddress);

    constructor(
        address _feeTokenAddress, 
        uint256 _launchFee, 
        address _uniswapFactory, 
        address _swapTokenAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        feeToken = IERC20(_feeTokenAddress);
        launchFee = _launchFee;
        uniswapFactory = _uniswapFactory;
        swapTokenAddress = _swapTokenAddress;
    }

    function setLaunchFee(uint256 _newFee) external onlyOwner {
        launchFee = _newFee;
        emit LaunchFeeUpdated(_newFee);
    }

    function setFeeTokenAddress(address _feeTokenAddress) external onlyOwner {
        feeToken = IERC20(_feeTokenAddress);
    }

    function setUniswapFactory(address _uniswapFactory) external onlyOwner {
        uniswapFactory = _uniswapFactory;
    }

    function setSwapTokenAddress(address _swapTokenAddress) external onlyOwner {
        swapTokenAddress = _swapTokenAddress;
        emit SwapTokenAddressUpdated(_swapTokenAddress);
    }
}