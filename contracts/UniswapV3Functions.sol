// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

library UniswapV3Functions {
    function swapExactInputSingle(
        ISwapRouter swapRouter,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });

        amountOut = swapRouter.exactInputSingle{value: amountIn}(params);
    }

    function calculateLiquidityAmounts(
        uint160 sqrtPriceX96,
        int24 minTick,
        int24 maxTick,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal pure returns (uint128 liquidity) {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(minTick),
            TickMath.getSqrtRatioAtTick(maxTick),
            amount0Desired,
            amount1Desired
        );
    }

    function calculateTickRange(uint256 minPrice, uint256 maxPrice) internal pure returns (int24 minTick, int24 maxTick) {
        minTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(minPrice) * 2**96));
        maxTick = TickMath.getTickAtSqrtRatio(uint160(sqrt(maxPrice) * 2**96));
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
}