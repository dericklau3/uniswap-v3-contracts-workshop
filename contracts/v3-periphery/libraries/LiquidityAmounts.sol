// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';

/// @title 流动性与 token 数量换算函数
/// @notice 根据价格区间和 token 数量计算流动性，或反向计算流动性对应的 token 数量
library LiquidityAmounts {
    /// @notice 将 uint256 安全向下转换为 uint128
    /// @param x 待转换的 uint256
    /// @return y 转换后的 uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @notice 计算给定 token0 数量在指定价格区间可获得的流动性
    /// @dev 计算 amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param amount0 投入的 token0 数量
    /// @return liquidity 可铸造的流动性
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice 计算给定 token1 数量在指定价格区间可获得的流动性
    /// @dev 计算 amount1 / (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param amount1 投入的 token1 数量
    /// @return liquidity 可铸造的流动性
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice 根据 token0、token1 数量、当前价格和区间边界计算最大可铸造流动性
    /// @dev 当前价格低于区间时头寸完全由 token0 构成；高于区间时完全由 token1 构成；
    /// 位于区间内时两种 token 都需要，最终流动性取两边可支持值中的较小者
    /// @param sqrtRatioX96 池当前平方根价格
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param amount0 投入的 token0 数量
    /// @param amount1 投入的 token1 数量
    /// @return liquidity 最大可铸造流动性
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @notice 计算给定流动性在指定价格区间对应的 token0 数量
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount0 对应的 token0 数量
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            FullMath.mulDiv(
                uint256(liquidity) << FixedPoint96.RESOLUTION,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /// @notice 计算给定流动性在指定价格区间对应的 token1 数量
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount1 对应的 token1 数量
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice 根据当前价格和区间边界计算给定流动性对应的 token0 与 token1 本金
    /// @dev 该结果只包含仍作为流动性工作的本金，不包含已累计手续费
    /// @param sqrtRatioX96 池当前平方根价格
    /// @param sqrtRatioAX96 第一个 tick 边界的平方根价格
    /// @param sqrtRatioBX96 第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount0 对应的 token0 数量
    /// @return amount1 对应的 token1 数量
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }
}
