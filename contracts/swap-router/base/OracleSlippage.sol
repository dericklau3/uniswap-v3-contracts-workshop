// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../interfaces/IOracleSlippage.sol';

import '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';
import '@uniswap/v3-periphery/contracts/base/BlockTimestamp.sol';
import '@uniswap/v3-periphery/contracts/libraries/Path.sol';
import '../../v3-periphery/libraries/PoolAddress.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';

abstract contract OracleSlippage is IOracleSlippage, PeripheryImmutableState, BlockTimestamp {
    using Path for bytes;

    /// @dev 返回指定池子在当前区块开始时的 tick 和当前 tick，用来识别本区块内价格是否突然偏离。
    function getBlockStartingAndCurrentTick(IUniswapV3Pool pool)
        internal
        view
        returns (int24 blockStartingTick, int24 currentTick)
    {
        uint16 observationIndex;
        uint16 observationCardinality;
        (, currentTick, observationIndex, observationCardinality, , , ) = pool.slot0();

        // 至少需要 2 个 observation，才能可靠计算本区块开始时的 tick。
        require(observationCardinality > 1, 'NEO');

        // 如果最新 observation 发生在过去区块，说明当前区块还没有改变 tick 的交易；
        // 因此 slot0.tick 就等于本区块开始 tick。最新 observation 一定已初始化，无需额外检查。
        (uint32 observationTimestamp, int56 tickCumulative, , ) = pool.observations(observationIndex);
        if (observationTimestamp != uint32(_blockTimestamp())) {
            blockStartingTick = currentTick;
        } else {
            uint256 prevIndex = (uint256(observationIndex) + observationCardinality - 1) % observationCardinality;
            (uint32 prevObservationTimestamp, int56 prevTickCumulative, , bool prevInitialized) =
                pool.observations(prevIndex);

            require(prevInitialized, 'ONI');

            uint32 delta = observationTimestamp - prevObservationTimestamp;
            blockStartingTick = int24((tickCumulative - prevTickCumulative) / delta);
        }
    }

    /// @dev 根据代币对和费率计算池子地址；设为 virtual，方便测试合约替换池子查找逻辑。
    function getPoolAddress(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view virtual returns (IUniswapV3Pool pool) {
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    /// @dev 返回给定路径的合成 TWAP tick 和当前 tick。
    /// 多跳路径会把中间代币的价格关系抵消，最终统一表示 tokenOut/tokenIn 价格；tick 越低代表成交价越差。
    function getSyntheticTicks(bytes memory path, uint32 secondsAgo)
        internal
        view
        returns (int256 syntheticAverageTick, int256 syntheticCurrentTick)
    {
        bool lowerTicksAreWorse;

        uint256 numPools = path.numPools();
        address previousTokenIn;
        for (uint256 i = 0; i < numPools; i++) {
            // 假设 path 已按实际 swap 顺序编码。
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();
            IUniswapV3Pool pool = getPoolAddress(tokenIn, tokenOut, fee);

            // 读取当前池子的平均 tick 和当前 tick。
            int256 averageTick;
            int256 currentTick;
            if (secondsAgo == 0) {
                // secondsAgo 为 0 时比较“本区块开始”到“当前”，用于防御同区块内的价格操纵。
                (averageTick, currentTick) = getBlockStartingAndCurrentTick(pool);
            } else {
                (averageTick, ) = OracleLibrary.consult(address(pool), secondsAgo);
                (, currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            }

            if (i == numPools - 1) {
                // 最后一跳的 tokenOut 是最终目标代币。根据 token 排序决定合成 tick 的方向，
                // 最终统一成“tick 越低，用户拿到的目标代币越少”的判断口径。
                lowerTicksAreWorse = tokenIn < tokenOut;
            } else {
                // 还有下一跳，移动 path 指针并记录上一跳输入代币，用于判断 tick 应加还是减。
                path = path.skipToken();
                previousTokenIn = tokenIn;
            }

            // 把每个池子的 tick 累加成一条合成价格路径；符号选择会让中间代币在价格表达式中抵消。
            bool add = (i == 0) || (previousTokenIn < tokenIn ? tokenIn < tokenOut : tokenOut < tokenIn);
            if (add) {
                syntheticAverageTick += averageTick;
                syntheticCurrentTick += currentTick;
            } else {
                syntheticAverageTick -= averageTick;
                syntheticCurrentTick -= currentTick;
            }
        }

        // 必要时翻转符号，确保最终“tick 变低 = 用户成交价变差”。
        if (!lowerTicksAreWorse) {
            syntheticAverageTick *= -1;
            syntheticCurrentTick *= -1;
        }
    }

    /// @dev 将 int256 转为 int24，溢出或下溢时回滚。
    function toInt24(int256 y) private pure returns (int24 z) {
        require((z = int24(y)) == y);
    }

    /// @dev 对每条 path 分别计算合成 TWAP tick 和当前 tick，再按每条路径分配的输入数量做加权平均。
    /// 所有 path 必须拥有相同的起点和终点；返回值统一表示 tokenOut/tokenIn，tick 越低越差。
    function getSyntheticTicks(
        bytes[] memory paths,
        uint128[] memory amounts,
        uint32 secondsAgo
    ) internal view returns (int256 averageSyntheticAverageTick, int256 averageSyntheticCurrentTick) {
        require(paths.length == amounts.length);

        OracleLibrary.WeightedTickData[] memory weightedSyntheticAverageTicks =
            new OracleLibrary.WeightedTickData[](paths.length);
        OracleLibrary.WeightedTickData[] memory weightedSyntheticCurrentTicks =
            new OracleLibrary.WeightedTickData[](paths.length);

        for (uint256 i = 0; i < paths.length; i++) {
            (int256 syntheticAverageTick, int256 syntheticCurrentTick) = getSyntheticTicks(paths[i], secondsAgo);
            weightedSyntheticAverageTicks[i].tick = toInt24(syntheticAverageTick);
            weightedSyntheticCurrentTicks[i].tick = toInt24(syntheticCurrentTick);
            weightedSyntheticAverageTicks[i].weight = amounts[i];
            weightedSyntheticCurrentTicks[i].weight = amounts[i];
        }

        averageSyntheticAverageTick = OracleLibrary.getWeightedArithmeticMeanTick(weightedSyntheticAverageTicks);
        averageSyntheticCurrentTick = OracleLibrary.getWeightedArithmeticMeanTick(weightedSyntheticCurrentTicks);
    }

    /// @notice 检查单条路径当前价格相对 TWAP 的偏离是否超过最大 tick 差。
    /// @dev 偏离过大时回滚，可作为 swap 前的 oracle 滑点保护。
    function checkOracleSlippage(
        bytes memory path,
        uint24 maximumTickDivergence,
        uint32 secondsAgo
    ) external view override {
        (int256 syntheticAverageTick, int256 syntheticCurrentTick) = getSyntheticTicks(path, secondsAgo);
        require(syntheticAverageTick - syntheticCurrentTick < maximumTickDivergence, 'TD');
    }

    /// @notice 检查多条拆单路径的加权当前价格相对加权 TWAP 的偏离是否过大。
    /// @dev amounts 表示每条路径分到的输入规模，用作 tick 加权平均的权重。
    function checkOracleSlippage(
        bytes[] memory paths,
        uint128[] memory amounts,
        uint24 maximumTickDivergence,
        uint32 secondsAgo
    ) external view override {
        (int256 averageSyntheticAverageTick, int256 averageSyntheticCurrentTick) =
            getSyntheticTicks(paths, amounts, secondsAgo);
        require(averageSyntheticAverageTick - averageSyntheticCurrentTick < maximumTickDivergence, 'TD');
    }
}
