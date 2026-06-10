// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 流动性数学库
/// @notice 把带符号的仓位变化安全应用到 uint128 活跃流动性。
/// @dev Pool 在加仓、减仓和跨 tick 时都使用同一语义：正数增加 liquidity，负数减少。
/// 单独封装可避免把负数错误转换成巨大 uint128，也防止减仓超过现有流动性。
library LiquidityMath {
    /// @notice 将带符号的流动性变化量应用到现有流动性，溢出或下溢时回退
    /// @param x 变化前的流动性
    /// @param y 流动性变化量，正数表示增加，负数表示减少
    /// @return z 变化后的流动性
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            require((z = x - uint128(-y)) < x, 'LS');
        } else {
            require((z = x + uint128(y)) >= x, 'LA');
        }
    }
}
