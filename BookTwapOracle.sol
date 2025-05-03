// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";


interface IChainLinkOracle {
    function latestAnswer() external view returns (int256);
}

contract BookTwapOracle {

    IUniswapV3Pool public immutable bookPool;
    IChainLinkOracle public immutable bnbChainlink;
    address public immutable token0;
    address public immutable token1;


    constructor(IUniswapV3Pool _bookPool, IChainLinkOracle _bnbChainlink) {
        bookPool = _bookPool;
        bnbChainlink = _bnbChainlink;

        token0 = _bookPool.token0();
        token1 = _bookPool.token1();

    }


    function _getTwap(uint32 _twapDuration) public view returns (int24) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = bookPool.observe(secondsAgo);
        int24 currentTwap = int24((tickCumulatives[1] - tickCumulatives[0]) / _twapDuration);

        return currentTwap;
    }

    function _getPriceFromTick(int24 tick) internal pure returns (uint256 priceU18) {
        priceU18 = OracleLibrary.getQuoteAtTick(
            tick,
            1e18, // fixed point to 18 decimals
            address(1), // since we want the price in terms of token0/token1
            address(0)
        );
    }


    function name(bytes calldata) public pure  returns (string memory) {
        return "BOOK USD Twap Oracle";
    }

    function symbol(bytes calldata) public pure  returns (string memory) {
        return "BOOK-USD";
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(uint32 _duration) external view returns (uint amountOut) {
        int256 latestPrice = bnbChainlink.latestAnswer();
        int24 twapTick = _getTwap(_duration);
        uint256 price = _getPriceFromTick(twapTick);
        amountOut = price * uint256(latestPrice) / 1e8;

    }

}