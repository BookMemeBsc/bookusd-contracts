// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IERC721Receiver.sol";

contract LpLocker is IERC721Receiver {
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    address public feeCollector;

    event DepositCreated(uint256 indexed tokenId);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    struct Deposit {
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        address token0;
        address token1;
        uint256 tokenId;
    }

    mapping(uint256 => Deposit) public deposits;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        feeCollector = msg.sender;
    }

    function setFeeCollector(address _feeCollector) external {
        require(msg.sender == feeCollector, "Not Fee Collector");
        feeCollector = _feeCollector;
    }

    function deposit(uint256 tokenId) external {
        require(deposits[tokenId].tokenId == 0, "Already Deposited");

        // Transfer the NFT to this contract
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        // Create a deposit
        _createDeposit(tokenId);
    }

    function _createDeposit(uint256 tokenId) internal {
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
            liquidity: liquidity,
            tickLower: tickLower,
            tickUpper: tickUpper,
            token0: token0,
            token1: token1,
            tokenId: tokenId
        });

        emit DepositCreated(tokenId);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) public returns (uint256 amount0, uint256 amount1) {
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: feeCollector,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        emit FeesCollected(tokenId, amount0, amount1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
