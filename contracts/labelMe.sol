// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

contract ReleaseNFT is ERC721, ERC721Enumerable, Ownable {
    uint256 private _nextTokenId;

    mapping(uint256 => string) private _tokenIPFSHashes;

    constructor(string memory name, string memory symbol, address initialOwner) 
        ERC721(name, symbol) 
        Ownable(initialOwner)
    {
        _nextTokenId = 1;
    }

    function mintRelease(address to, string memory ipfsHash) external onlyOwner returns (uint256) {
        uint256 newTokenId = _nextTokenId;
        _safeMint(to, newTokenId);
        _tokenIPFSHashes[newTokenId] = ipfsHash;
        _nextTokenId++;
        return newTokenId;
    }

    function getIPFSHash(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _tokenIPFSHashes[tokenId];
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract Releaser is Ownable {
    IERC20 public feeToken;
    uint256 public releaseFee;
    IUniswapV3Factory public uniswapFactory;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // Arbitrum WETH address
    string public labelName;
    ReleaseNFT public releaseNFT;
    uint256 public requiredEthAmount;
    bool public onlyLabelOwner;
    address public swapTokenAddress;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

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

    Release[] public releases;

    event NewReleaseCreated(address indexed newTokenAddress, string name, string symbol, uint256 totalSupply, uint256 liquidityPercentage, int24 minTick, int24 maxTick, address poolAddress, uint256 nftTokenId);
    event ReleaseFeeUpdated(uint256 newFee);
    event FeesClaimed(uint256 indexed releaseIndex, uint256 amount0, uint256 amount1, address collector);
    event RequiredEthAmountUpdated(uint256 newAmount);
    event OnlyLabelOwnerUpdated(bool newValue);

    constructor(
        address _feeTokenAddress,
        uint256 _releaseFee,
        address _uniswapFactory,
        string memory _labelName,
        address _owner,
        uint256 _initialRequiredEthAmount,
        bool _onlyLabelOwner,
        address _swapTokenAddress
    ) Ownable(_owner) {
        feeToken = IERC20(_feeTokenAddress);
        releaseFee = _releaseFee;
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);
        labelName = _labelName;
        releaseNFT = new ReleaseNFT(string(abi.encodePacked(_labelName, " Releases")), "RLSNFT", _owner);
        requiredEthAmount = _initialRequiredEthAmount;
        onlyLabelOwner = _onlyLabelOwner;
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
    ) external payable {
        if (onlyLabelOwner) {
            require(msg.sender == owner(), "Only label owner can create releases");
        }
        require(msg.value >= requiredEthAmount, "Insufficient ETH sent");
        require(feeToken.transferFrom(msg.sender, owner(), releaseFee), "Release fee transfer failed");
        require(swapTokenAddress != address(0), "Swap token address not set");

        // Swap ETH for tokens
        uint256 deadline = block.timestamp + 15; // 15 seconds from now
        uint256 amountOut = swapExactInputSingle(msg.value, deadline);

        require(amountOut > 0, "Swap failed");

        // Transfer the swapped tokens to this contract
        TransferHelper.safeTransferFrom(swapTokenAddress, address(this), address(this), amountOut);

        // Create the new token
        string memory fullName = string(abi.encodePacked(labelName, " ", name));
        NewToken newToken = new NewToken(fullName, symbol, totalSupply, address(this));
        
        // Create Uniswap pool for the new token
        address poolAddress = uniswapFactory.createPool(address(newToken), WETH, 3000);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        uint160 sqrtPriceX96 = uint160(sqrt(amountOut * 2**192 / totalSupply));
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
        pool.mint(address(this), minTick, maxTick, uint128(liquidityAmount), abi.encode(amount0, amount1));

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
        require(releaseNFT.ownerOf(release.nftTokenId) == msg.sender, "Only the NFT holder can collect fees");

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

    function setReleaseFee(uint256 _newFee) external onlyOwner {
        releaseFee = _newFee;
        emit ReleaseFeeUpdated(_newFee);
    }

    function setRequiredEthAmount(uint256 _newAmount) external onlyOwner {
        requiredEthAmount = _newAmount;
        emit RequiredEthAmountUpdated(_newAmount);
    }

    function setOnlyLabelOwner(bool _onlyLabelOwner) external onlyOwner {
        onlyLabelOwner = _onlyLabelOwner;
        emit OnlyLabelOwnerUpdated(_onlyLabelOwner);
    }

    function swapExactInputSingle(uint256 amountIn, uint256 deadline) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(WETH, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: swapTokenAddress,
                fee: 3000,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle{value: amountIn}(params);
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

contract NewToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 totalSupply, address owner) ERC20(name, symbol) {
        _mint(owner, totalSupply);
    }
}

contract LabelFactory is Ownable {
    IERC20 public feeToken;
    uint256 public launchFee;
    address public uniswapFactory;
    address public swapTokenAddress;

    event LabelCreated(address indexed releaserAddress, string labelName, address owner);
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

    function createLabel(
        string memory labelName, 
        uint256 initialReleaseFee, 
        uint256 initialRequiredEthAmount,
        bool initialOnlyLabelOwner
    ) external returns (address) {
        require(feeToken.transferFrom(msg.sender, owner(), launchFee), "Launch fee transfer failed");

        Releaser newReleaser = new Releaser(
            address(feeToken),
            initialReleaseFee,
            uniswapFactory,
            labelName,
            msg.sender,
            initialRequiredEthAmount,
            initialOnlyLabelOwner,
            swapTokenAddress
        );

        emit LabelCreated(address(newReleaser), labelName, msg.sender);
        return address(newReleaser);
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