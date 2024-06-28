// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

enum ChartDuration { Day, Week, Month, Quarter, Year }

contract ArtChartFactory is Ownable(msg.sender) {
    bool public onlyAllowOwner;

    event ChartCreated(address chartAddress, bool isOpenChart, address[] allowedNFTContracts, bool onlyAllowOwner, ChartDuration duration);

    constructor(bool _onlyAllowOwner) {
        onlyAllowOwner = _onlyAllowOwner;
    }

    modifier onlyAuthorized() {
        require(!onlyAllowOwner || msg.sender == owner(), "Not authorized");
        _;
    }

    function createChart(
        address stakingToken,
        bool isOpenChart,
        address[] memory allowedNFTContracts,
        bool _onlyAllowOwner,
        ChartDuration _duration
    ) external onlyAuthorized returns (address) {
        ArtChart newChart = new ArtChart(
            stakingToken,
            isOpenChart,
            allowedNFTContracts,
            _onlyAllowOwner,
            _duration,
            msg.sender
        );
        
        emit ChartCreated(address(newChart), isOpenChart, allowedNFTContracts, _onlyAllowOwner, _duration);
        return address(newChart);
    }

    function setOnlyAllowOwner(bool _onlyAllowOwner) external onlyOwner {
        onlyAllowOwner = _onlyAllowOwner;
    }
}

contract ArtChart is Ownable {
    struct Entry {
        address nftContract;
        uint256 tokenId;
        address uniswapV3Pool;
        uint256 stakedAmount;
        uint256 observationIndex;
    }

    struct ChartEntry {
        address nftContract;
        uint256 tokenId;
        uint256 score;
    }

    IERC20 public stakingToken;
    uint256 private _periodCounter;
    uint256 public constant CHART_SIZE = 10;
    uint256 public immutable PERIOD_DURATION;
    uint256 public immutable WITHDRAWAL_WINDOW;

    bool public isOpenChart;
    bool public onlyAllowOwner;
    ChartDuration public duration;
    mapping(address => bool) public allowedNFTContracts;

    mapping(uint256 => mapping(address => mapping(uint256 => Entry))) public entries;
    mapping(uint256 => ChartEntry[]) public periodCharts;
    mapping(uint256 => uint256) public periodStartTimes;

    event EntrySubmitted(uint256 indexed period, address indexed nftContract, uint256 indexed tokenId);
    event PointsUpdated(uint256 indexed period, address indexed nftContract, uint256 indexed tokenId, uint256 newScore);
    event ChartFinalized(uint256 indexed period);
    event StakeWithdrawn(uint256 indexed period, address indexed nftContract, uint256 indexed tokenId, uint256 amount);
    event StakeRolledOver(uint256 indexed fromPeriod, uint256 indexed toPeriod, address indexed nftContract, uint256 tokenId, uint256 amount);

    modifier onlyAuthorized() {
        require(!onlyAllowOwner || msg.sender == owner(), "Not authorized");
        _;
    }

    constructor(
        address _stakingToken,
        bool _isOpenChart,
        address[] memory _allowedNFTContracts,
        bool _onlyAllowOwner,
        ChartDuration _duration,
        address _owner
    ) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        isOpenChart = _isOpenChart;
        onlyAllowOwner = _onlyAllowOwner;
        duration = _duration;
        
        if (!isOpenChart) {
            for (uint i = 0; i < _allowedNFTContracts.length; i++) {
                allowedNFTContracts[_allowedNFTContracts[i]] = true;
            }
        }

        if (duration == ChartDuration.Day) {
            PERIOD_DURATION = 1 days;
            WITHDRAWAL_WINDOW = 1 hours;
        } else if (duration == ChartDuration.Week) {
            PERIOD_DURATION = 7 days;
            WITHDRAWAL_WINDOW = 1 days;
        } else if (duration == ChartDuration.Month) {
            PERIOD_DURATION = 30 days;
            WITHDRAWAL_WINDOW = 2 days;
        } else if (duration == ChartDuration.Quarter) {
            PERIOD_DURATION = 90 days;
            WITHDRAWAL_WINDOW = 3 days;
        } else if (duration == ChartDuration.Year) {
            PERIOD_DURATION = 365 days;
            WITHDRAWAL_WINDOW = 7 days;
        } else {
            revert("Invalid duration");
        }

        _periodCounter = 1; // Start from period 1
        periodStartTimes[_periodCounter] = block.timestamp;

    }

    function submitEntry(address nftContract, uint256 tokenId, address uniswapV3Pool) external onlyAuthorized {
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Must own the NFT");
        require(isOpenChart || allowedNFTContracts[nftContract], "NFT contract not allowed");
        require(entries[_periodCounter][nftContract][tokenId].nftContract == address(0), "Entry already exists");

        entries[_periodCounter][nftContract][tokenId] = Entry({
            nftContract: nftContract,
            tokenId: tokenId,
            uniswapV3Pool: uniswapV3Pool,
            stakedAmount: 0,
            observationIndex: 0
        });

        emit EntrySubmitted(_periodCounter, nftContract, tokenId);
    }

    function stakeTokens(address nftContract, uint256 tokenId, uint256 amount) external onlyAuthorized {
        Entry storage entry = entries[_periodCounter][nftContract][tokenId];
        require(entry.nftContract != address(0), "Entry does not exist");

        stakingToken.transferFrom(msg.sender, address(this), amount);
        entry.stakedAmount += amount;

        updatePoints(nftContract, tokenId);
    }

    function updateObservationIndex(address nftContract, uint256 tokenId) external onlyAuthorized {
        Entry storage entry = entries[_periodCounter][nftContract][tokenId];
        require(entry.nftContract != address(0), "Entry does not exist");

        IUniswapV3Pool pool = IUniswapV3Pool(entry.uniswapV3Pool);
        (uint256 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, , , ) = pool.slot0();
        entry.observationIndex = uint256(observationIndex);

        updatePoints(nftContract, tokenId);
    }

    function updatePoints(address nftContract, uint256 tokenId) internal {
        Entry storage entry = entries[_periodCounter][nftContract][tokenId];
        uint256 newScore = entry.stakedAmount + entry.observationIndex;

        emit PointsUpdated(_periodCounter, nftContract, tokenId, newScore);
    }

    function finalizePeriodChart() external onlyAuthorized {
        require(block.timestamp >= periodStartTimes[_periodCounter] + PERIOD_DURATION, "Period not yet over");

        // ... (rest of the function remains the same)

        // Start new period
        _periodCounter++;
        periodStartTimes[_periodCounter] = block.timestamp;
    }

    function getPeriodChart(uint256 period) external view returns (ChartEntry[] memory) {
        return periodCharts[period];
    }

    function getCurrentPeriod() external view returns (uint256) {
        return _periodCounter;
    }

    function withdrawStakedTokens(address nftContract, uint256 tokenId) external onlyAuthorized {
        require(_periodCounter > 1, "No completed periods yet");
        uint256 lastCompletedPeriod = _periodCounter - 1;
        Entry storage lastPeriodEntry = entries[lastCompletedPeriod][nftContract][tokenId];
        require(lastPeriodEntry.nftContract != address(0), "Entry does not exist");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Must own the NFT");
        require(block.timestamp <= periodStartTimes[_periodCounter] + WITHDRAWAL_WINDOW, "Withdrawal window closed");

        uint256 amount = lastPeriodEntry.stakedAmount;
        lastPeriodEntry.stakedAmount = 0;
        stakingToken.transfer(msg.sender, amount);

        emit StakeWithdrawn(lastCompletedPeriod, nftContract, tokenId, amount);
    }

    function rolloverStakes() external onlyAuthorized {
        require(_periodCounter > 1, "No completed periods yet");
        require(block.timestamp > periodStartTimes[_periodCounter] + WITHDRAWAL_WINDOW, "Withdrawal window still open");

        uint256 lastCompletedPeriod = _periodCounter - 1;
        uint256 currentPeriod = _periodCounter;

        // ... (rest of the function remains the same)
    }

    function getCurrentChartPositions() external view returns (ChartEntry[] memory) {
        ChartEntry[] memory allEntries = new ChartEntry[](1000); // Arbitrary large number, adjust as needed
        uint256 entryCount = 0;

        for (address nftContract = address(1); nftContract != address(0); nftContract = address(uint160(nftContract) + 1)) {
            for (uint256 tokenId = 0; tokenId < type(uint256).max; tokenId++) {
                Entry storage entry = entries[_periodCounter][nftContract][tokenId];
                if (entry.nftContract != address(0)) {
                    uint256 score = entry.stakedAmount + entry.observationIndex;
                    allEntries[entryCount] = ChartEntry(nftContract, tokenId, score);
                    entryCount++;

                    if (entryCount == allEntries.length) {
                        break;
                    }
                }
            }

            if (entryCount == allEntries.length) {
                break;
            }
        }

        // Resize the array to the actual number of entries
        ChartEntry[] memory resizedEntries = new ChartEntry[](entryCount);
        for (uint256 i = 0; i < entryCount; i++) {
            resizedEntries[i] = allEntries[i];
        }

        // Sort the entries
        for (uint256 i = 0; i < entryCount - 1; i++) {
            for (uint256 j = 0; j < entryCount - i - 1; j++) {
                if (resizedEntries[j].score < resizedEntries[j + 1].score) {
                    ChartEntry memory temp = resizedEntries[j];
                    resizedEntries[j] = resizedEntries[j + 1];
                    resizedEntries[j + 1] = temp;
                }
            }
        }

        return resizedEntries;
    }

    function isNFTContractAllowed(address nftContract) public view returns (bool) {
        return isOpenChart || allowedNFTContracts[nftContract];
    }

    function setOnlyAllowOwner(bool _onlyAllowOwner) external onlyOwner {
        onlyAllowOwner = _onlyAllowOwner;
    }
}