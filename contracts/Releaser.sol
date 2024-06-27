// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import './UniswapV3Functions.sol';
import "./ReleaseNFT.sol";
import "./ReleaseToken.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract Releaser {
    struct Release {
        address tokenAddress;
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 liquidityPercentage;
        int24 minTick;
        int24 maxTick;
        address poolAddress;
        uint256 nftTokenId;
    }

    IERC20 public immutable feeToken;
    uint256 public releaseFee;
    IUniswapV3Factory public immutable uniswapFactory;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    string public labelName;
    ReleaseNFT public immutable releaseNFT;
    uint256 public requiredEthAmount;
    bool public onlyLabelOwnerCanCreate; 
    address public swapTokenAddress;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC721 public immutable labelOwnershipToken;
    uint256 public immutable labelOwnershipTokenId;

    mapping(address => bool) public whitelistedCreators;
    Release[] public releases;

    event NewReleaseCreated(address indexed newTokenAddress, string name, string symbol, uint256 totalSupply, uint256 liquidityPercentage, int24 minTick, int24 maxTick, address poolAddress, uint256 nftTokenId);
    event FeesClaimed(uint256 indexed releaseIndex, uint256 amount0, uint256 amount1, address collector);

    modifier onlyLabelOwnerOrWhitelisted() {
        require(
            labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender || 
            whitelistedCreators[msg.sender],
            "Not authorized"
        );
        _;
    }

    constructor(
        address _feeTokenAddress,
        uint256 _releaseFee,
        address _uniswapFactory,
        string memory _labelName,
        address _labelOwnershipTokenAddress,
        uint256 _labelOwnershipTokenId,
        uint256 _initialRequiredEthAmount,
        bool _onlyLabelOwnerCanCreate,
        address _swapTokenAddress
    ) {
        feeToken = IERC20(_feeTokenAddress);
        releaseFee = _releaseFee;
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
        labelName = _labelName;
        labelOwnershipToken = IERC721(_labelOwnershipTokenAddress);
        labelOwnershipTokenId = _labelOwnershipTokenId;
        releaseNFT = new ReleaseNFT(string(abi.encodePacked(_labelName, " Releases")), "RLSNFT", address(this));
        requiredEthAmount = _initialRequiredEthAmount;
        onlyLabelOwnerCanCreate = _onlyLabelOwnerCanCreate;
        swapTokenAddress = _swapTokenAddress;
    }

    function createNewRelease(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 liquidityPercentage,
        string memory ipfsHash,
        uint256 minPrice,
        uint256 maxPrice
    ) external payable onlyLabelOwnerOrWhitelisted {
        require(msg.value >= requiredEthAmount, "Insufficient ETH sent");
        require(feeToken.transferFrom(msg.sender, labelOwnershipToken.ownerOf(labelOwnershipTokenId), releaseFee), "Fee transfer failed");

        uint256 halfEthAmount = msg.value / 2;
        uint256 amountOut = UniswapV3Functions.swapExactInputSingle(
            swapRouter,
            WETH,
            swapTokenAddress,
            3000,
            halfEthAmount,
            0,
            0
        );

        require(amountOut > 0, "Swap failed");
        IERC20(swapTokenAddress).transfer(labelOwnershipToken.ownerOf(labelOwnershipTokenId), amountOut);

        string memory fullName = string(abi.encodePacked(labelName, " ", name));
        ReleaseToken newToken = new ReleaseToken(fullName, symbol, totalSupply, address(this));
        
        address poolAddress = uniswapFactory.createPool(address(newToken), WETH, 3000);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        uint160 sqrtPriceX96 = uint160(sqrt(totalSupply * 2**192 / msg.value));
        pool.initialize(sqrtPriceX96);

        uint256 liquidityAmount = (totalSupply * liquidityPercentage) / 100;

        int24 minTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(minPrice) * 2**96));
        int24 maxTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(maxPrice) * 2**96));

        newToken.approve(address(this), liquidityAmount);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(minTick),
            TickMath.getSqrtRatioAtTick(maxTick),
            uint128(liquidityAmount)
        );

        if (address(newToken) < WETH) {
            pool.mint(address(this), minTick, maxTick, uint128(liquidityAmount), abi.encode(amount0, halfEthAmount));
        } else {
            pool.mint(address(this), minTick, maxTick, uint128(liquidityAmount), abi.encode(halfEthAmount, amount1));
        }

        IWETH(WETH).deposit{value: address(this).balance}();

        if (liquidityPercentage < 100) {
            newToken.transfer(msg.sender, totalSupply - liquidityAmount);
        }
        
        uint256 nftTokenId = releaseNFT.mintRelease(msg.sender, ipfsHash);
        
        releases.push(Release(address(newToken), fullName, symbol, totalSupply, liquidityPercentage, minTick, maxTick, poolAddress, nftTokenId));
        
        emit NewReleaseCreated(address(newToken), fullName, symbol, totalSupply, liquidityPercentage, minTick, maxTick, poolAddress, nftTokenId);
    }

    function collectFees(uint256 releaseIndex) external {
        require(releaseIndex < releases.length, "Invalid release index");
        Release memory release = releases[releaseIndex];
        require(releaseNFT.ownerOf(release.nftTokenId) == msg.sender, "Only NFT holder can collect fees");

        IUniswapV3Pool pool = IUniswapV3Pool(release.poolAddress);
        
        (uint256 amount0, uint256 amount1) = pool.collect(
            address(this),
            release.minTick,
            release.maxTick,
            type(uint128).max,
            type(uint128).max
        );

        if (amount0 > 0) {
            IERC20(pool.token0()).transfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            IERC20(pool.token1()).transfer(msg.sender, amount1);
        }

        emit FeesClaimed(releaseIndex, amount0, amount1, msg.sender);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    receive() external payable {}
}