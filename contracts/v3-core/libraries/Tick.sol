// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './TickMath.sol';
import './LiquidityMath.sol';

/// @title Tick 状态管理库
/// @notice 管理每个价格边界的流动性变化，以及该边界两侧的手续费和时间累计值。
/// @dev tick 可以理解为价格轴上的离散刻度。LP 选择 `[tickLower, tickUpper)` 后：
/// - 价格从左向右跨过下边界，仓位开始参与交易，活跃流动性增加；
/// - 价格继续跨过上边界，仓位停止参与交易，活跃流动性减少；
/// - 反向跨越时，上述变化符号相反。
///
/// 一个 tick 可能同时被许多仓位当作边界，因此 `liquidityGross` 统计绝对总量，
/// `liquidityNet` 统计从左向右跨越时对全池活跃流动性的净影响。swap 只需在跨 tick 时应用净值，
/// 无需遍历所有使用该边界的 LP。
///
/// `outside` 系列字段只保存边界某一侧的累计值。价格每次跨越时执行
/// `outside = global - outside`，即可把记录从旧的一侧翻转到新的一侧。上下边界各保存一份 outside，
/// 就能用“全局 - 下方 - 上方”算出任意仓位区间内部的手续费与时间累计值。
library Tick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    /// @notice 一个已初始化价格边界的共享状态。
    struct Info {
        // 以该 tick 作为下边界或上边界的头寸流动性总和
        uint128 liquidityGross;
        // 价格从左向右跨越该 tick 时应增加的净流动性；反向跨越时取相反数
        int128 liquidityNet;
        // 相对于当前 tick，记录该 tick“另一侧”的每单位流动性手续费增长
        // 该值只有相对意义，其基准取决于 tick 首次初始化的时刻
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // 该 tick 另一侧的 tick 时间累计值
        int56 tickCumulativeOutside;
        // 该 tick 另一侧的每单位流动性秒数累计值
        // 该值只有相对意义，其基准取决于 tick 首次初始化的时刻
        uint160 secondsPerLiquidityOutsideX128;
        // 价格位于该 tick 另一侧的累计秒数
        // 该值只有相对意义，其基准取决于 tick 首次初始化的时刻
        uint32 secondsOutside;
        // tick 是否已初始化，语义上等价于 liquidityGross != 0
        // 单独保存该标记可避免跨越新初始化 tick 时产生昂贵的首次 SSTORE
        bool initialized;
    }

    /// @notice 根据 tick 间距计算单个 tick 可承载的最大流动性
    /// @dev 在池构造函数中调用。把 uint128 的容量平均分配给全部可用 tick，防止某个边界累计值溢出
    /// @param tickSpacing 可初始化 tick 之间的间距，tick 必须是其整数倍
    ///     例如间距为 3 时，可初始化的 tick 为 ..., -6, -3, 0, 3, 6, ...
    /// @return 单个 tick 可承载的最大流动性
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        // tickSpacing 决定有多少个可用 tick；可用 tick 越多，每个 tick 允许的最大 liquidity 越小；
        // 这个函数就是根据 tickSpacing 计算每个 tick 的最大流动性上限。
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        return type(uint128).max / numTicks;
    }

    /// @notice 计算指定头寸价格区间内部的手续费增长
    /// @dev 核心恒等式是：
    /// `inside = global - below(tickLower) - above(tickUpper)`。
    /// 难点在于 outside 的物理字段会随当前价格所在侧而改变语义，因此要先结合 `tickCurrent`
    /// 判断字段本身就是目标侧累计值，还是应该用 `global - outside` 取补集。
    ///
    /// 业务上，LP 只应赚取市场价格位于其区间、该流动性真正参与成交期间产生的手续费。
    /// 该公式把全池累计手续费切出中间区间，避免为每位 LP 单独跟踪每笔 swap。
    /// @param self 保存所有已初始化 tick 信息的映射
    /// @param tickLower 头寸的下边界 tick
    /// @param tickUpper 头寸的上边界 tick
    /// @param tickCurrent 当前 tick
    /// @param feeGrowthGlobal0X128 token0 自池创建以来的全局每单位流动性手续费增长
    /// @param feeGrowthGlobal1X128 token1 自池创建以来的全局每单位流动性手续费增长
    /// @return feeGrowthInside0X128 头寸区间内部 token0 的每单位流动性手续费增长
    /// @return feeGrowthInside1X128 头寸区间内部 token1 的每单位流动性手续费增长
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        // 计算下边界以下的手续费增长。当前价格在边界哪一侧，决定 outside 值是否需要用全局值取补集
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // 计算上边界以上的手续费增长
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    /// @notice 更新 tick 的流动性状态，并返回其初始化状态是否发生切换
    /// @dev 铸造或销毁头寸时，下边界与上边界都会调用本函数。
    /// 对一份新增流动性 L：下边界记录 `+L`，上边界记录 `-L`，所以价格从左向右移动时，
    /// 进入区间增加 L，离开区间减少 L。销毁时 `liquidityDelta` 为负，效果自然反转。
    ///
    /// 首次初始化一个位于当前价格左侧的 tick 时，需要把当前全局累计值写入 outside。
    /// 这相当于声明“创建这个边界之前的全部历史都发生在它的外侧”，让后续补集计算保持连续。
    /// @param self 保存所有已初始化 tick 信息的映射
    /// @param tick 待更新的 tick
    /// @param tickCurrent 当前 tick
    /// @param liquidityDelta 新增或移除的头寸流动性
    /// @param feeGrowthGlobal0X128 token0 的全局每单位流动性手续费增长
    /// @param feeGrowthGlobal1X128 token1 的全局每单位流动性手续费增长
    /// @param secondsPerLiquidityCumulativeX128 池自初始化以来的每单位流动性秒数累计值
    /// @param tickCumulative 池自初始化以来的 tick 时间累计值
    /// @param time 转为 uint32 的当前区块时间戳
    /// @param upper 为 true 表示更新头寸上边界，为 false 表示更新下边界
    /// @param maxLiquidity 单个 tick 允许分配的最大流动性
    /// @return flipped tick 是否在已初始化与未初始化之间发生切换
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Tick.Info storage info = self[tick];

        // 本函数主要维护 liquidityGross 和 liquidityNet，同时在首次初始化时建立 outside 累计值基准

        // 该 tick 被所有头寸引用的总流动性
        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, 'LO');

        // 首次添加流动性或最后一份流动性被移除时，位图中的初始化标记需要翻转
        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // 约定 tick 初始化之前发生的全部增长都位于该 tick 下方
            // 若 tick 不高于当前价格，将当前全局累计值写入 outside，后续跨越时才能通过取补集保持语义正确
            if (tick <= tickCurrent) {
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // 从左向右跨越下边界时流动性生效，跨越上边界时流动性失效，因此上边界记录相反符号
        info.liquidityNet = upper
            ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice 清除指定 tick 的全部状态
    /// @param self 保存所有已初始化 tick 信息的映射
    /// @param tick 待清除的 tick
    function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice 价格跨越 tick 时切换该边界两侧的累计状态
    /// @dev 假设跨越前 outside 保存左侧累计值，而全局累计值等于左侧加右侧；
    /// 那么 `global - oldOutside` 正好得到右侧累计值。反向再次跨越时做同样运算又会恢复左侧值。
    /// 手续费、tick 时间积分、每份流动性秒数和经过秒数都使用同一翻转技巧。
    /// @param self 保存所有已初始化 tick 信息的映射
    /// @param tick 本次跨越的目标 tick
    /// @param feeGrowthGlobal0X128 token0 的全局每单位流动性手续费增长
    /// @param feeGrowthGlobal1X128 token1 的全局每单位流动性手续费增长
    /// @param secondsPerLiquidityCumulativeX128 当前每单位流动性秒数累计值
    /// @param tickCumulative 当前 tick 时间累计值
    /// @param time 当前区块时间戳
    /// @return liquidityNet 从左向右跨越时应应用的净流动性变化，反向跨越时由调用方取反
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time
    ) internal returns (int128 liquidityNet) {
        Tick.Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }
}
