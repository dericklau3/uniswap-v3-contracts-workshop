// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.8.0;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

/// @title 预言机辅助库
/// @notice 提供读取和组合 Uniswap V3 池预言机数据的函数
/// @dev Core Oracle 返回累计 tick 与累计每份流动性秒数，本库把它们转换成平均 tick、
/// 调和平均流动性、token 报价和多池合成价格等应用层结果。
///
/// TWAP 只能降低单笔交易操纵瞬时价格的风险，不代表绝对安全。使用方仍需选择合适窗口、
/// 确认 observation 历史足够长，并评估池规模与窗口内的低流动性时段。
library OracleLibrary {
    /// @notice 计算指定 V3 池在给定时间窗口内的时间加权平均 tick 和调和平均流动性
    /// @dev 读取 `[secondsAgo, 0]` 两个累计值后做差并除以窗口长度。
    /// 平均 tick 对应时间加权几何平均价格；调和平均流动性更敏感地反映低流动性时段，
    /// 窗口内哪怕短暂出现极低流动性，也会明显拉低结果。
    /// @param pool 待读取的池地址
    /// @param secondsAgo 时间窗口长度，单位为秒
    /// @return arithmeticMeanTick 从 block.timestamp - secondsAgo 到当前时刻的算术平均 tick
    /// @return harmonicMeanLiquidity 同一时间窗口内的调和平均流动性
    function consult(address pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        require(secondsAgo != 0, 'BP');

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        uint160 secondsPerLiquidityCumulativesDelta =
            secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / secondsAgo);
        // tick 除法存在负余数时继续减 1，确保始终向负无穷取整
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % secondsAgo != 0)) arithmeticMeanTick--;

        // 此处使用乘法而非移位，确保 harmonicMeanLiquidity 不会溢出 uint128
        uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
        harmonicMeanLiquidity = uint128(secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32));
    }

    /// @notice 根据 tick 和基础 token 数量计算可兑换的报价 token 数量
    /// @param tick 用于报价的 tick
    /// @param baseAmount 待换算的基础 token 数量
    /// @param baseToken baseAmount 所对应的 ERC20 地址
    /// @param quoteToken 报价 token 的 ERC20 地址
    /// @return quoteAmount baseAmount 对应的报价 token 数量
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // 平方根价格平方后不溢出 uint256 时使用 Q192 路径，否则降低精度使用 Q128 路径
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice 返回指定池最旧 observation 距当前时刻的秒数
    /// @param pool 待读取的 Uniswap V3 池地址
    /// @return secondsAgo 池中最旧 observation 距当前时刻的秒数
    function getOldestObservationSecondsAgo(address pool) internal view returns (uint32 secondsAgo) {
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(pool).slot0();
        require(observationCardinality > 0, 'NI');

        (uint32 observationTimestamp, , , bool initialized) =
            IUniswapV3Pool(pool).observations((observationIndex + 1) % observationCardinality);

        // 扩容尚未写满时，下一个索引可能未初始化；此时最旧 observation 固定在索引 0
        if (!initialized) {
            (observationTimestamp, , , ) = IUniswapV3Pool(pool).observations(0);
        }

        secondsAgo = uint32(block.timestamp) - observationTimestamp;
    }

    /// @notice 返回指定池在当前区块开始时的 tick
    /// @param pool Uniswap V3 池地址
    /// @return 当前区块开始时池所在的 tick
    function getBlockStartingTickAndLiquidity(address pool) internal view returns (int24, uint128) {
        (, int24 tick, uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(pool).slot0();

        // 至少需要两条 observation 才能可靠计算区块开始 tick
        require(observationCardinality > 1, 'NEO');

        // 若最新 observation 早于当前区块，说明本区块尚无改变 tick 的交易，
        // 因此 slot0 中的 tick 就是区块开始 tick。最新 observation 保证已初始化，无需额外检查
        (uint32 observationTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, ) =
            IUniswapV3Pool(pool).observations(observationIndex);
        if (observationTimestamp != uint32(block.timestamp)) {
            return (tick, IUniswapV3Pool(pool).liquidity());
        }

        uint256 prevIndex = (uint256(observationIndex) + observationCardinality - 1) % observationCardinality;
        (
            uint32 prevObservationTimestamp,
            int56 prevTickCumulative,
            uint160 prevSecondsPerLiquidityCumulativeX128,
            bool prevInitialized
        ) = IUniswapV3Pool(pool).observations(prevIndex);

        require(prevInitialized, 'ONI');

        uint32 delta = observationTimestamp - prevObservationTimestamp;
        tick = int24((tickCumulative - prevTickCumulative) / delta);
        uint128 liquidity =
            uint128(
                (uint192(delta) * type(uint160).max) /
                    (uint192(secondsPerLiquidityCumulativeX128 - prevSecondsPerLiquidityCumulativeX128) << 32)
            );
        return (tick, liquidity);
    }

    /// @notice 计算加权算术平均 tick 所需的数据
    struct WeightedTickData {
        int24 tick;
        uint128 weight;
    }

    /// @notice 根据 tick 与权重数组计算加权算术平均 tick
    /// @param weightedTickData tick 与权重数据数组
    /// @return weightedArithmeticMeanTick 加权算术平均 tick
    /// @dev 各项通常应来自底层 token 相同的池；否则必须确认 tick 可比较，包括 token 小数位差异
    /// @dev tick 的加权算术平均对应价格的加权几何平均
    function getWeightedArithmeticMeanTick(WeightedTickData[] memory weightedTickData)
        internal
        pure
        returns (int24 weightedArithmeticMeanTick)
    {
        // 累加 tick 与对应权重的乘积
        int256 numerator;

        // 累加权重总和
        uint256 denominator;

        // 单项乘积可放入 152 位，数组长度约达到 2**104 才可能使该累加逻辑溢出
        for (uint256 i; i < weightedTickData.length; i++) {
            numerator += weightedTickData[i].tick * int256(weightedTickData[i].weight);
            denominator += weightedTickData[i].weight;
        }

        weightedArithmeticMeanTick = int24(numerator / int256(denominator));
        // 存在负余数时继续减 1，确保始终向负无穷取整
        if (numerator < 0 && (numerator % int256(denominator) != 0)) weightedArithmeticMeanTick--;
    }

    /// @notice 返回合成 tick，表示 tokens 中第一个 token 相对于最后一个 token 的价格
    /// @dev 用于计算多跳路径两端资产的相对价格；每一对相邻 token 必须对应一个 tick
    /// @param tokens 路径中的 token 合约地址
    /// @param ticks 每对相邻 token 的价格 tick
    /// @return syntheticTick 表示路径首尾 token 相对价格的合成 tick
    function getChainedPrice(address[] memory tokens, int24[] memory ticks)
        internal
        pure
        returns (int256 syntheticTick)
    {
        require(tokens.length - 1 == ticks.length, 'DL');
        for (uint256 i = 1; i <= ticks.length; i++) {
            // 根据相邻 token 的地址排序决定 tick 符号，再累加为合成 tick，
            // 使路径中的中间 token 在价格比连乘中相互抵消
            tokens[i - 1] < tokens[i] ? syntheticTick += ticks[i - 1] : syntheticTick -= ticks[i - 1];
        }
    }
}
