// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title 压缩存储 tick 初始化状态的位图库
/// @notice 将每个可用 tick 是否已初始化压缩到 uint256 位图中
/// @dev swap 只关心“下一个有流动性变化的 tick”，若逐个检查整个 int24 价格轴会非常昂贵。
/// 本库先用 tickSpacing 把可用 tick 压缩成连续编号，再让每个 uint256 word 保存 256 个布尔标记。
/// 搜索时对一个 word 做掩码，并用 BitMath 直接定位最近的置位 bit；若本 word 没有结果，
/// 返回 word 边界，让 Pool 下一轮继续搜索相邻 word。
library TickBitmap {
    /// @notice 计算 tick 在位图中的 word 位置和位偏移
    /// @param tick 已按 tickSpacing 压缩后的 tick
    /// @return wordPos 保存该标记的映射键
    /// @return bitPos 标记在 uint256 word 中的位位置
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        // 右移 8 位等价于除以 256，得到该压缩 tick 属于哪个 word。
        wordPos = int16(tick >> 8);
        // 低 8 位等价于模 256，得到它在 word 内的 bit 位置。
        bitPos = uint8(tick % 256);
    }

    /// @notice 翻转指定 tick 的初始化状态
    /// @dev 同一个 tick 首次获得流动性时由 0 变 1，最后一份流动性移除时由 1 变 0
    /// @param self tick 位图映射
    /// @param tick 待翻转的原始 tick
    /// @param tickSpacing 可用 tick 的间距
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0); // 只有 tickSpacing 的整数倍才是可用边界
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        // 左移生成只有目标位置为 1 的掩码。
        uint256 mask = 1 << bitPos;
        // XOR 会翻转该 bit：首次有仓位使用边界时 0 -> 1，最后一份仓位移除时 1 -> 0。
        self[wordPos] ^= mask;
    }

    /// @notice 在当前 word 范围内查找左侧或右侧最近的已初始化 tick
    /// @dev 每次最多检查 256 个压缩 tick；若本 word 没有命中，则返回该 word 的边界并标记 initialized=false
    /// @param self tick 位图映射
    /// @param tick 搜索起点
    /// @param tickSpacing 可用 tick 的间距
    /// @param lte 是否向左搜索小于或等于起点的最近 tick
    /// @return next 当前 word 内最近的已初始化 tick，或没有命中时的 word 边界 tick
    /// @return initialized 返回的 tick 是否确实已初始化
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // Solidity 除法向零取整，此处修正为向负无穷取整

        // 向左搜索，当前 tick 本身也参与匹配
        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // 构造从最低位到 bitPos（含）的全 1 掩码，只保留当前位及其左侧候选
            // currectTick = 81609
            // bitPos = 152,    1 << bitPos = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            //            (1 << bitPos) - 1 = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"
            //                         mask = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"
            //                self[wordPos] = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            //                       masked = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            // & 运算：如果两位都为1，结果为1；否则结果为0。
            uint256 masked = self[wordPos] & mask;

            // 若没有已初始化 tick，则返回当前 word 最左侧对应的 tick，供交换循环继续搜索前一个 word
            initialized = masked != 0;
            // 理论上可能溢出或下溢，但外部对 tickSpacing 和 tick 的范围限制会阻止这种情况
            // BitMath.mostSignificantBit(masked) = tickLower 78200 / 200 % 256
            // (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing = tickLower
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // 向右搜索必须从下一个压缩 tick 开始，因为要求结果严格大于当前 tick
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // 构造从 bitPos 到最高位的全 1 掩码，只保留当前位及其右侧候选
            // currectTick = 81607
            // bitPos = 153, (1 << bitPos) - 1 = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111"
            //                            mask = "1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            //                   self[wordPos] = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            //                          masked = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            // ~ 运算：对每一位取反，即0变1，1变0
            uint256 mask = ~((1 << bitPos) - 1);
            // & 运算：如果两位都为1，结果为1；否则结果为0。
            uint256 masked = self[wordPos] & mask;

            // 若没有已初始化 tick，则返回当前 word 最右侧对应的 tick，供交换循环继续搜索下一个 word
            initialized = masked != 0;
            // 理论上可能溢出或下溢，但外部对 tickSpacing 和 tick 的范围限制会阻止这种情况
            // BitMath.leastSignificantBit(masked) = tickUpper 84200 / 200 % 256
            // (compressed + 1 - int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing = tickLower
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }
}
