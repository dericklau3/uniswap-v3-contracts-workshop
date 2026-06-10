// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/UnsafeMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';

/// @title 基于 Q64.96 平方根价格和流动性的部分数学函数
/// @notice 暴露 core SqrtPriceMath 中根据价格区间和流动性计算 token 数量变化的两个函数
/// @dev 该副本供外围估值与展示代码使用，只保留 amount0/amount1 delta 两个方向。
/// `roundUp=true` 适合计算调用方至少应支付多少，`roundUp=false` 适合计算最多可安全给出多少。
library SqrtPriceMathPartial {
    /// @notice 计算两个价格之间对应的 token0 数量变化
    /// @dev 计算 liquidity / sqrt(lower) - liquidity / sqrt(upper)，即
    /// liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 可用流动性
    /// @param roundUp 是否向上取整 token 数量
    /// @return amount0 在两个价格之间维持指定流动性所需的 token0 数量
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
                ? UnsafeMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice 计算两个价格之间对应的 token1 数量变化
    /// @dev 计算 liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 可用流动性
    /// @param roundUp 是否向上取整 token 数量
    /// @return amount1 在两个价格之间维持指定流动性所需的 token1 数量
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            roundUp
                ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }
}
