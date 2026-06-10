// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

/// @title V3 报价跨 tick 计数
/// @notice 统计起止价格之间实际跨越的初始化流动性边界，供 QuoterV2 估算复杂度。
/// @dev 只有 bitmap 中置位的 tick 会触发 Pool 的 outside 与 liquidity 更新；空 tick 不计入。
library PoolTicksCounter {
    /// @dev 统计 tickBefore 与 tickAfter 之间会在交换中产生跨越 gas 成本的已初始化 tick 数量。
    /// 若起点或终点本身已初始化，是否计数取决于交换方向：价格向上时不计起点但计终点；
    /// 价格向下时计起点但不计终点。这与池实际跨 tick 时应用流动性变化的边界语义一致。
    function countInitializedTicksCrossed(
        IUniswapV3Pool self,
        int24 tickBefore,
        int24 tickAfter
    ) internal view returns (uint32 initializedTicksCrossed) {
        int16 wordPosLower;
        int16 wordPosHigher;
        uint8 bitPosLower;
        uint8 bitPosHigher;
        bool tickBeforeInitialized;
        bool tickAfterInitialized;

        {
            // 计算交换前后 active tick 在位图中的 word 键和位偏移
            int16 wordPos = int16((tickBefore / self.tickSpacing()) >> 8);
            uint8 bitPos = uint8((tickBefore / self.tickSpacing()) % 256);

            int16 wordPosAfter = int16((tickAfter / self.tickSpacing()) >> 8);
            uint8 bitPosAfter = uint8((tickAfter / self.tickSpacing()) % 256);

            // tickAfter 已初始化时，只有向上交换才应把它作为本次跨越终点计数。
            // 若 tickAfter 本身是可初始化 tick、对应位已置 1 且交换向下，则应从计数中排除
            tickAfterInitialized =
                ((self.tickBitmap(wordPosAfter) & (1 << bitPosAfter)) > 0) &&
                ((tickAfter % self.tickSpacing()) == 0) &&
                (tickBefore > tickAfter);

            // tickBefore 已初始化时，只有向下交换才会实际跨离该边界并产生相应成本；
            // 使用与上面相同的位图判断修正起点计数
            tickBeforeInitialized =
                ((self.tickBitmap(wordPos) & (1 << bitPos)) > 0) &&
                ((tickBefore % self.tickSpacing()) == 0) &&
                (tickBefore < tickAfter);

            if (wordPos < wordPosAfter || (wordPos == wordPosAfter && bitPos <= bitPosAfter)) {
                wordPosLower = wordPos;
                bitPosLower = bitPos;
                wordPosHigher = wordPosAfter;
                bitPosHigher = bitPosAfter;
            } else {
                wordPosLower = wordPosAfter;
                bitPosLower = bitPosAfter;
                wordPosHigher = wordPos;
                bitPosHigher = bitPos;
            }
        }

        // 遍历 tick 位图并统计被跨越的已初始化位。
        // 第一张位图只保留下界位及其右侧的搜索区间
        uint256 mask = type(uint256).max << bitPosLower;
        while (wordPosLower <= wordPosHigher) {
            // 到达最后一个位图 word 时，再用上界掩码排除终点之后的位
            if (wordPosLower == wordPosHigher) {
                mask = mask & (type(uint256).max >> (255 - bitPosHigher));
            }

            uint256 masked = self.tickBitmap(wordPosLower) & mask;
            initializedTicksCrossed += countOneBits(masked);
            wordPosLower++;
            // 后续完整 word 使用全 1 掩码，统计其中全部已初始化 tick
            mask = type(uint256).max;
        }

        if (tickAfterInitialized) {
            initializedTicksCrossed -= 1;
        }

        if (tickBeforeInitialized) {
            initializedTicksCrossed -= 1;
        }

        return initializedTicksCrossed;
    }

    function countOneBits(uint256 x) private pure returns (uint16) {
        uint16 bits = 0;
        while (x != 0) {
            bits++;
            x &= (x - 1);
        }
        return bits;
    }
}
