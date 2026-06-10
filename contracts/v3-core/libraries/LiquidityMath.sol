// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 流动性数学库
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
