// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

/// @title 预言机
/// @notice 提供可用于时间加权平均价格和时间加权流动性的累计数据
/// @dev 预言机数据以 observation 形式保存在环形数组中。池初始化时数组长度为 1，任何人都可以承担
/// 扩容所需的 SSTORE 成本。扩容后的槽位会随交易逐步写满；全部写满后，新 observation 会覆盖最旧数据。
/// 无论数组长度如何，调用 observe() 并传入 0 都可读取当前时刻的最新累计值。
library Oracle {
    struct Observation {
        // 记录 observation 的区块时间戳
        uint32 blockTimestamp;
        // tick 时间累计值，即各时间段 active tick 与持续秒数乘积的总和
        int56 tickCumulative;
        // 每单位流动性秒数累计值，即 elapsedSeconds / max(1, liquidity) 的累计结果
        uint160 secondsPerLiquidityCumulativeX128;
        // 该 observation 槽位是否已经写入有效数据
        bool initialized;
    }

    /// @notice 根据经过的时间、当前 tick 和流动性，把上一条 observation 推演为新 observation
    /// @dev blockTimestamp 在时间顺序上必须不早于 last.blockTimestamp；支持 uint32 时间戳发生零次或一次回绕
    /// @param last 用作推演起点的 observation
    /// @param blockTimestamp 新 observation 的时间戳
    /// @param tick 新 observation 时刻的 active tick
    /// @param liquidity 新 observation 时刻的区间内总流动性
    /// @return Observation 推演得到的新 observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        // 累计每单位流动性秒数 += 时间差 * 2**128 / max(1, liquidity)
        return
            Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: last.tickCumulative + int56(tick) * delta,
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                initialized: true
            });
    }

    /// @notice 写入第一个槽位以初始化预言机数组，整个数组生命周期只调用一次
    /// @param self 存储 observation 的数组
    /// @param time 截断为 uint32 的初始化时间戳
    /// @return cardinality 已写入有效数据的元素数量
    /// @return cardinalityNext 数组计划容量
    function initialize(Observation[65535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({
            blockTimestamp: time,
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        return (1, 1);
    }

    /// @notice 向环形数组写入一条预言机 observation
    /// @dev 每个区块最多写入一次。index 指向最近写入的元素，index 和 cardinality 由池状态负责维护。
    /// 只有写指针到达当前容量末尾且 cardinalityNext 更大时才启用扩展容量，以保持 observation 的时间顺序。
    /// @param self 存储 observation 的数组
    /// @param index 最近写入 observation 的索引
    /// @param blockTimestamp 新 observation 的时间戳
    /// @param tick 新 observation 时刻的 active tick
    /// @param liquidity 新 observation 时刻的区间内总流动性
    /// @param cardinality 当前已启用的环形数组容量
    /// @param cardinalityNext 计划启用的数组容量
    /// @return indexUpdated 新写入 observation 的索引
    /// @return cardinalityUpdated 更新后的已启用容量
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        // 当前区块已经写过 observation 时直接返回，避免同一时间戳重复采样
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // 写指针到达旧容量末尾后，才切换到预先申请的新容量
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        // 更新 Oracle.Observation
        self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
    }

    /// @notice 预先准备最多可保存 `next` 条 observation 的存储槽
    /// @dev 扩容只预热存储，不会立即增加有效历史数据数量；后续交换会逐槽写入
    /// @param self 存储 observation 的数组
    /// @param current 当前计划容量
    /// @param next 请求的新计划容量
    /// @return next 最终采用的计划容量
    function grow(
        Observation[65535] storage self,
        uint16 current,
        uint16 next
    ) internal returns (uint16) {
        require(current > 0, 'I');
        // 新容量不大于当前容量时无需操作
        if (next <= current) return current;
        // 预先写入每个槽位，避免后续交换承担从零到非零的首次 SSTORE 成本
        // initialized 仍为 false，因此这些占位时间戳不会被当作有效 observation
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice 比较两个 uint32 时间戳的先后顺序
    /// @dev 支持零次或一次回绕；按真实时间顺序，a 和 b 都必须不晚于 time
    /// @param time 截断为 32 位的当前时间戳
    /// @param a 待比较的时间戳
    /// @param b 待比较的时间戳
    /// @return bool 按时间顺序 a 是否早于或等于 b
    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // 两者均未跨越回绕点时可直接比较
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice 查找包围目标时间的两条 observation，即 beforeOrAt <= target <= atOrAfter
    /// @dev 结果可能是同一条或相邻两条 observation。目标必须位于最旧和最新已存历史之间。
    /// 环形数组按物理索引可能不连续，因此使用扩展逻辑索引进行二分，再通过取模读取实际槽位。
    /// @param self 存储 observation 的数组
    /// @param time 当前区块时间戳
    /// @param target 目标 observation 时间戳
    /// @param index 最近写入 observation 的索引
    /// @param cardinality 当前已启用的环形数组容量
    /// @return beforeOrAt 发生在目标时刻或目标之前的 observation
    /// @return atOrAfter 发生在目标时刻或目标之后的 observation
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // 最旧 observation 的逻辑索引
        uint256 r = l + cardinality - 1; // 最新 observation 的逻辑索引
        uint256 i;
        while (true) {
            // 在逻辑时间有序区间中取中点
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // 命中尚未启用的槽位时，继续向时间更近的一侧搜索
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // 目标位于相邻两条 observation 之间时即找到答案
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice 获取包围目标时间的前后两条 observation
    /// @dev 假定至少存在一条已初始化 observation。observeSingle() 使用结果计算目标时刻的反事实累计值。
    /// @param self 存储 observation 的数组
    /// @param time 当前区块时间戳
    /// @param target 目标时间戳
    /// @param tick 当前 active tick，用于推演尚未落盘的最新 observation
    /// @param index 最近写入 observation 的索引
    /// @param liquidity 调用时的池内有效流动性
    /// @param cardinality 当前已启用的环形数组容量
    /// @return beforeOrAt 发生在目标时刻或目标之前的 observation
    /// @return atOrAfter 发生在目标时刻或目标之后的 observation
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // 先假设目标不早于最新 observation，以便走常见的快速路径
        beforeOrAt = self[index];

        // 目标不早于最新 observation 时可直接返回或从最新值推演
        // currentTime, lastTime, target
        // lastTime <= target
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // 最新 observation 恰好位于目标时刻，无需提供右侧 observation
                return (beforeOrAt, atOrAfter);
            } else {
                // 目标晚于最新落盘值，使用当前 tick 和流动性推演到目标时刻
                return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity));
            }
        }

        // 目标早于最新 observation，改为从最旧 observation 检查历史覆盖范围
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // 目标不能早于池中仍然保留的最旧历史
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // 目标位于已存历史内部，二分查找最接近的前后 observation
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @notice 返回指定回溯时刻的 tick 和每单位流动性秒数累计值
    /// @dev 若目标早于最旧 observation 则回退。secondsAgo 为 0 时返回当前累计值。
    /// 若目标落在两条 observation 之间，则按时间比例线性插值得到目标时刻的反事实累计值。
    /// @param self 存储 observation 的数组
    /// @param time 当前区块时间戳
    /// @param secondsAgo 从当前时刻向前回溯的秒数
    /// @param tick 当前 tick
    /// @param index 最近写入 observation 的索引
    /// @param liquidity 当前区间内流动性
    /// @param cardinality 当前已启用的环形数组容量
    /// @return tickCumulative 目标时刻的 tick 时间累计值
    /// @return secondsPerLiquidityCumulativeX128 目标时刻的每单位流动性秒数累计值
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        // 回溯 0 秒时返回当前累计值；若本区块尚未写入，则先在内存中推演
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        uint32 target = time - secondsAgo;

        // currentTime, lastTime, target
        // 如果target == lastTime  返回 beforeOrAt = last
        // 否则返回 obsesrvationBefore < target < observationAfter
        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, liquidity, cardinality);

        if (target == beforeOrAt.blockTimestamp) {
            // 目标正好命中左侧 observation
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // 目标正好命中右侧 observation
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // 目标位于两条 observation 中间，按时间比例插值累计值
            // before，after之间的时间差值
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            // before, target之间的时间差值
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            // tickCumulative = before.tickCumulative + ((after.tickCumulative - before.tickCumulative) / timeDelta) * targetDelta
            // secondsPerLiquidityCumulative = before.secondsPerLiquidityCumulative + (after.secondsPerLiquidityCumulative - before.secondsPerLiquidityCumulative) * targetDelta / timeDelta
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / observationTimeDelta) *
                    targetDelta,
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    /// @notice 批量返回 secondsAgos 中每个回溯时刻对应的累计值
    /// @dev 任一目标早于最旧 observation 时回退
    /// @param self 存储 observation 的数组
    /// @param time 当前区块时间戳
    /// @param secondsAgos 各查询点距当前时刻的秒数
    /// @param tick 当前 tick
    /// @param index 最近写入 observation 的索引
    /// @param liquidity 当前区间内流动性
    /// @param cardinality 当前已启用的环形数组容量
    /// @return tickCumulatives 各目标时刻的 tick 时间累计值
    /// @return secondsPerLiquidityCumulativeX128s 各目标时刻的每单位流动性秒数累计值
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        require(cardinality > 0, 'I');

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                liquidity,
                cardinality
            );
        }
    }
}
