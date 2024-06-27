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


contract LabelOwnershipToken is ERC721, Ownable {
    uint256 private _tokenIdCounter;

    constructor(address initialOwner) ERC721("Label Ownership Token", "LOT") Ownable(initialOwner) {
        _tokenIdCounter = 1;
    }

    function mint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _safeMint(to, tokenId);
        _tokenIdCounter++;
        return tokenId;
    }
}

// Add IWETH interface
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract Releaser {
    IERC20 public feeToken;
    uint256 public releaseFee;
    IUniswapV3Factory public uniswapFactory;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // Arbitrum WETH address
    string public labelName;
    ReleaseNFT public releaseNFT;
    uint256 public requiredEthAmount;
    bool public onlyLabelOwnerCanCreate; 
    address public swapTokenAddress;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // New variables for ERC721 ownership
    IERC721 public labelOwnershipToken;
    uint256 public labelOwnershipTokenId;

// Mapping to store whitelisted addresses
    mapping(address => bool) public whitelistedCreators;

 // array to keep track of whitelisted addresses
    address[] public whitelistedCreatorsList;

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

 modifier onlyLabelOwnerOrWhitelisted() {
        require(
            labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender || 
            whitelistedCreators[msg.sender],
            "Not authorized to perform this action"
        );
        _;
    }

 modifier onlyLabelOwner() {
        require(
            labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender,
            "Not authorized to perform this action"
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

   // Function to check if an address is whitelisted
    function isWhitelisted(address creator) public view returns (bool) {
        return whitelistedCreators[creator];
    }

    // Function to get all whitelisted addresses
    function getWhitelistedCreators() public view returns (address[] memory) {
        return whitelistedCreatorsList;
    }

    // Update the addToWhitelist function
    function addToWhitelist(address[] memory creators) external {
        require(labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender, "Only label owner can modify whitelist");
        for (uint i = 0; i < creators.length; i++) {
            if (!whitelistedCreators[creators[i]]) {
                whitelistedCreators[creators[i]] = true;
                whitelistedCreatorsList.push(creators[i]);
            }
        }
    }

    // Update the removeFromWhitelist function
    function removeFromWhitelist(address[] memory creators) external {
        require(labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender, "Only label owner can modify whitelist");
        for (uint i = 0; i < creators.length; i++) {
            if (whitelistedCreators[creators[i]]) {
                whitelistedCreators[creators[i]] = false;
                // Remove from the list
                for (uint j = 0; j < whitelistedCreatorsList.length; j++) {
                    if (whitelistedCreatorsList[j] == creators[i]) {
                        whitelistedCreatorsList[j] = whitelistedCreatorsList[whitelistedCreatorsList.length - 1];
                        whitelistedCreatorsList.pop();
                        break;
                    }
                }
            }
        }
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
        if (onlyLabelOwnerCanCreate) {
            require(
                labelOwnershipToken.ownerOf(labelOwnershipTokenId) == msg.sender || 
                whitelistedCreators[msg.sender],
                "Not authorized to create releases"
            );
        }
        require(msg.value >= requiredEthAmount, "Insufficient ETH sent");
        require(feeToken.transferFrom(msg.sender, labelOwnershipToken.ownerOf(labelOwnershipTokenId), releaseFee), "Release fee transfer failed");
        require(swapTokenAddress != address(0), "Swap token address not set");

        uint256 halfEthAmount = msg.value / 2;

        // Swap half of the ETH for tokens
        uint256 deadline = block.timestamp + 15; // 15 seconds from now
        uint256 amountOut = swapExactInputSingle(halfEthAmount, deadline);

        require(amountOut > 0, "Swap failed");

        // Transfer the swapped tokens to the label owner
        IERC20(swapTokenAddress).transfer(labelOwnershipToken.ownerOf(labelOwnershipTokenId), amountOut);

        // Create the new token with 0 decimals
        string memory fullName = string(abi.encodePacked(labelName, " ", name));
        NewToken newToken = new NewToken(fullName, symbol, totalSupply, address(this));
        
        // Create Uniswap pool for the new token
        address poolAddress = uniswapFactory.createPool(address(newToken), WETH, 3000);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        uint160 sqrtPriceX96 = uint160(sqrt(totalSupply * 2**192 / msg.value));
        pool.initialize(sqrtPriceX96);

        uint256 liquidityAmount = (totalSupply * liquidityPercentage) / 100;

        int24 minTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(minPrice) * 2**96));
        int24 maxTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(maxPrice) * 2**96));

        newToken.approve(address(this), liquidityAmount);

        // Add liquidity to the pool with half ETH and corresponding amount of new tokens
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

        // Wrap remaining ETH to WETH
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

    function setReleaseFee(uint256 _newFee) external onlyLabelOwner {
        releaseFee = _newFee;
        emit ReleaseFeeUpdated(_newFee);
    }

    function setRequiredEthAmount(uint256 _newAmount) external onlyLabelOwner {
        requiredEthAmount = _newAmount;
        emit RequiredEthAmountUpdated(_newAmount);
    }

    function setOnlyLabelOwnerCanCreate(bool _onlyLabelOwnerCanCreate) external onlyLabelOwner {
        onlyLabelOwnerCanCreate = _onlyLabelOwnerCanCreate;
        emit OnlyLabelOwnerUpdated(_onlyLabelOwnerCanCreate);
    }

    function swapExactInputSingle(uint256 amountIn, uint256 deadline) internal returns (uint256 amountOut) {
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

        // The router will wrap ETH automatically
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
    constructor(string memory name, string memory symbol, uint256 totalSupply, address owner) 
        ERC20(name, symbol)
    {
        _mint(owner, totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
}

contract LabelFactory is Ownable {
    IERC20 public feeToken;
    uint256 public launchFee;
    address public uniswapFactory;
    address public swapTokenAddress;
    LabelOwnershipToken public labelOwnershipToken;

    event LabelCreated(address indexed releaserAddress, string labelName, uint256 labelOwnershipTokenId);
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
        labelOwnershipToken = new LabelOwnershipToken(address(this));
    }

    function createLabel(
        string memory labelName, 
        uint256 initialReleaseFee, 
        uint256 initialRequiredEthAmount,
        bool initialOnlyLabelOwnerCanCreate
    ) external returns (address) {
        require(feeToken.transferFrom(msg.sender, owner(), launchFee), "Launch fee transfer failed");

        uint256 labelOwnershipTokenId = labelOwnershipToken.mint(msg.sender);

        Releaser newReleaser = new Releaser(
            address(feeToken),
            initialReleaseFee,
            uniswapFactory,
            labelName,
            address(labelOwnershipToken),
            labelOwnershipTokenId,
            initialRequiredEthAmount,
            initialOnlyLabelOwnerCanCreate,
            swapTokenAddress
        );

        emit LabelCreated(address(newReleaser), labelName, labelOwnershipTokenId);
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