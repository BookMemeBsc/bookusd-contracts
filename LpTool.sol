// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "./interfaces/IERC721Receiver.sol";

contract LpTool is IERC721Receiver {
    address public constant BOOK = 0xC9Ad421f96579AcE066eC188a7Bba472fB83017F;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    uint24 public constant poolFee = 10000;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    IUniswapV3Pool public immutable bookPool;

    int24 public immutable tickSpacing;

    address public admin;

    event DepositCreated(address indexed owner, uint256 tokenId, uint256 bonus);
    event FeesCollected(address indexed owner, uint256 tokenId, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(address indexed owner, uint256 tokenId, uint256 amount0, uint256 amount1);

    struct Deposit {
        address owner;
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        address token0;
        address token1;
        uint256 timestamp;
        uint256 bonus;
        bool withdrawn;
        uint256 tokenId;
    }

    mapping(uint256 => Deposit) public deposits;

    mapping(address => mapping(uint256 => uint256)) public userDeposits;

    mapping(address => uint256) public userDepositsCount;

    uint256 public totalDeposits;

    uint256 public bookBonusesGiven;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, address _pool) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        bookPool = IUniswapV3Pool(_pool);
        tickSpacing = IUniswapV3Pool(_pool).tickSpacing();
        admin = msg.sender;
    }

    function bookAvailableForBonus() public view returns (uint256) {
        return IERC20(BOOK).balanceOf(address(this));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        // get position information
        // _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function setAdmin(address _admin) external {
        require(msg.sender == admin, "Not admin");
        admin = _admin;
    }

    function getDeposits(address user) external view returns (Deposit[] memory) {
        Deposit[] memory senderDeposits = new Deposit[](userDepositsCount[user]);

        for (uint256 i = 0; i < userDepositsCount[user]; i++) {
            senderDeposits[i] = deposits[userDeposits[user][i]];
        }

        return senderDeposits;
    }

    function _createDeposit(address owner, uint256 tokenId, uint256 _bonus) internal {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        deposits[tokenId] = Deposit({
            owner: owner,
            liquidity: liquidity,
            tickLower: tickLower,
            tickUpper: tickUpper,
            token0: token0,
            token1: token1,
            timestamp: block.timestamp,
            bonus: _bonus,
            withdrawn: false,
            tokenId: tokenId
        });

        emit DepositCreated(owner, tokenId, _bonus);
    }

    function calculateBonus(int24 _minTick, int24 _maxTick) public pure returns (int256) {
        int256 minimum = int256(_minTick) * 100;
        int256 bonus = minimum / _maxTick;

        if (bonus < 68)
            // Max Bonus for 50x
            return 50;
        else if (bonus < 75)
            // Max Bonus for 20x position
            return 40;
        else if (bonus < 82)
            // Bonus for 10x position
            return 30;
        else if (bonus < 87)
            // Bonus for 5x position
            return 20;
        else if (bonus < 95)
            // Bonus for 2x
            return 5;
        else return 0;
    }

    function getTwap() public view returns (int24) {
        uint32 _twapDuration = 60;
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = bookPool.observe(secondsAgo);
        int24 currentTwap = int24((tickCumulatives[1] - tickCumulatives[0]) / _twapDuration);

        return currentTwap;
    }

    /// @notice Calls the mint function defined in periphery,
    /// @param _bookAmount Amount of BOOK to be deposited
    /// @param _maxTick The maximum tick of the position
    /// @param _minTick The minimum tick of the position
    /// @param _lockPosition If the position should be locked
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(
        uint256 _bookAmount,
        int24 _maxTick,
        int24 _minTick,
        bool _lockPosition
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        TransferHelper.safeTransferFrom(BOOK, msg.sender, address(this), _bookAmount);

        uint256 positionAmount = _bookAmount;

        uint256 bonus = 0;

        if (_lockPosition) {
            bonus = (_bookAmount * uint256(calculateBonus(_minTick, _maxTick))) / 100;
            if (bonus > bookAvailableForBonus()) {
                bonus = bookAvailableForBonus();
            }
            positionAmount += bonus;
        }

        TransferHelper.safeApprove(BOOK, address(nonfungiblePositionManager), positionAmount);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: WBNB,
            token1: BOOK,
            fee: poolFee,
            tickLower: _minTick,
            tickUpper: _maxTick,
            amount0Desired: 0,
            amount1Desired: positionAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: _lockPosition ? address(this) : msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        if (_lockPosition) {
            _createDeposit(msg.sender, tokenId, bonus);

            userDepositsCount[msg.sender] += 1;
            userDeposits[msg.sender][userDepositsCount[msg.sender] - 1] = tokenId;
            totalDeposits += 1;

            bookBonusesGiven += bonus;
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) public returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position
        require(msg.sender == deposits[tokenId].owner, "Not the owner");

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // send collected feed back to owner
        if (amount0 > 0 || amount1 > 0) {
            _sendToOwner(tokenId, amount0, amount1);
        }
        emit FeesCollected(msg.sender, tokenId, amount0, amount1);
    }

    /// @notice A function that decreases the current liquidity.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function removeLiquidity(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");

        require(!deposits[tokenId].withdrawn, "Already withdrawn");

        require(getTwap() < deposits[tokenId].tickLower, "Twap is higher than min tick");

        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        nonfungiblePositionManager.decreaseLiquidity(params);

        (amount0, amount1) = nonfungiblePositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        deposits[tokenId].withdrawn = true;

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);

        emit LiquidityRemoved(msg.sender, tokenId, amount0, amount1);
    }

    function adminWithdrawToken(address _token, uint256 _amount) external {
        require(msg.sender == admin, "Not admin");
        TransferHelper.safeTransfer(_token, msg.sender, _amount);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721
    function retrieveNFT(address user, uint256 tokenId) internal {
        // must be the owner of the NFT
        require(user == deposits[tokenId].owner, "Not the owner");
        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(address(this), user, tokenId);
        //remove information related to tokenId
        delete deposits[tokenId];
    }
}
