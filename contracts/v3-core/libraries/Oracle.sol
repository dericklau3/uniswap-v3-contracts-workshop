// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

/// @title Uniswap V3 池内置的时间加权预言机
/// @notice 记录 tick 与活跃流动性随时间的累计值，供外部计算 TWAP 和时间加权平均流动性
/// @dev 本库不直接存储“某个 token 值多少钱”，而是维护两条只增不减的时间积分曲线：
/// - tickCumulative：对 active tick 按秒积分。两个时刻的累计值之差除以时间差，即算术平均 tick；
/// - secondsPerLiquidityCumulativeX128：对 1 / activeLiquidity 按秒积分。两个时刻的差值可反推出
///   该时间窗口内的调和平均流动性。
///
/// 业务例子：假设过去 30 分钟内，前 10 分钟 tick 为 100，后 20 分钟 tick 为 400，
/// 则 tick 累计增量为 100 * 600 + 400 * 1200 = 540000，平均 tick 为 540000 / 1800 = 300。
/// 调用方再通过 TickMath 把平均 tick 300 转换为价格。相比只读取当前价格，这种时间平均价格更难被
/// 单笔大额 swap 瞬时操纵，因此常用于借贷协议估值、抵押品清算和链上限价判断。
///
/// observation 保存在固定上限为 65535 的环形数组中。池初始化时只启用 1 个槽位，任何人都可以调用
/// increaseObservationCardinalityNext() 间接承担 grow() 的扩容成本。新槽位不会立刻产生历史数据，而会
/// 在后续发生 mint、burn 或 swap 时逐步写入。启用容量全部写满后，新 observation 会覆盖最旧记录，
/// 因此容量越大，通常可查询的历史窗口越长，但首次扩容和后续填充也需要更多 gas。
///
/// observation 只在池状态发生操作时落盘，不会每秒写链。例如上一条记录在 12:00，下一笔交易发生在
/// 12:10，observe() 查询 12:05 或当前时刻时，会根据这段时间内有效的 tick 和 liquidity 在内存中推演
/// 或在线性区间内插值，无需真的保存 600 条逐秒记录。
library Oracle {
    /// @notice 某个时间点的预言机累计值快照
    /// @dev 快照保存的是从池初始化至 blockTimestamp 的累计结果，而不是该时刻的瞬时价格。
    /// 因此计算某段时间的数据时必须使用两个 observation 做差，不能单独把 tickCumulative 当作价格。
    struct Observation {
        // 快照时间，取 block.timestamp 的低 32 位；约每 136 年回绕一次。
        uint32 blockTimestamp;
        // tick 的时间积分：Σ(activeTick * 该 tick 持续秒数)。
        // 例如 tick 100 持续 20 秒后切换为 tick 250 并持续 10 秒，累计增量为 100*20 + 250*10 = 4500。
        int56 tickCumulative;
        // 每单位活跃流动性的时间积分：Σ(持续秒数 / max(1, liquidity))，使用 Q128 定点数保存精度。
        // 流动性越低，同样一秒产生的增量越大；因此它适合通过倒数关系计算一段时间的调和平均流动性。
        uint160 secondsPerLiquidityCumulativeX128;
        // true 表示该槽位已经写入真实快照；grow() 仅预热的槽位仍为 false，查询时必须跳过。
        bool initialized;
    }

    /// @notice 根据经过的时间、当前 tick 和流动性，把上一条 observation 推演为新 observation
    /// @dev tick 和 liquidity 表示 last.blockTimestamp 到 blockTimestamp 这段时间内生效的状态。
    /// 池合约会先用旧状态写完截至当前时刻的累计值，再更新 tick 或 liquidity，避免把过去时间错误计入新状态。
    ///
    /// 例如 last 位于第 100 秒，tickCumulative 为 5000；随后 tick 200 保持到第 130 秒，
    /// 新累计值就是 5000 + 200 * 30 = 11000。若期间 active liquidity 为 1000，
    /// secondsPerLiquidity 累计值则增加 30 * 2^128 / 1000。
    ///
    /// uint32 减法刻意依赖无检查溢出语义，从而支持时间戳零次或一次回绕。例如 last 接近 2^32，
    /// blockTimestamp 已回绕为较小数值时，差值仍代表真实经过秒数。调用方必须保证时间顺序正确。
    /// @param last 用作推演起点的 observation
    /// @param blockTimestamp 新 observation 的时间戳
    /// @param tick 从 last 到 blockTimestamp 期间生效的 active tick
    /// @param liquidity 从 last 到 blockTimestamp 期间生效的池内活跃流动性
    /// @return Observation 推演得到的新 observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        // liquidity 为 0 时以 1 作为分母，避免除零；左移 128 位把结果编码为 Q128 定点数。
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
    /// @dev 初始化时累计值均从 0 开始，槽位 0 成为当前最旧和最新的 observation。
    /// 例如池在时间 100 创建，则第一次快照是 (time=100, tickCumulative=0, secondsPerLiquidity=0)；
    /// 后续在时间 160 写入时，才会把初始化后的 60 秒状态累计进去。
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
    ///
    /// 环形覆盖例子：cardinality 为 3 且当前 index 为 2 时，下一条写入索引为 (2 + 1) % 3 = 0，
    /// 原来索引 0 的最旧记录被覆盖。若 cardinalityNext 已扩到 5，则 index=2 时先把有效容量切换为 5，
    /// 下一条改写索引 3，保留索引 0 的旧历史，直到 5 个槽位都被逐步填满。
    ///
    /// 同一时间戳内可能连续发生多笔 swap，但第一笔已经记录了到该秒为止的累计值。后续写入直接返回，
    /// 因为经过时间为 0，不会增加任何累计值，也无需重复支付 SSTORE。
    /// @param self 存储 observation 的数组
    /// @param index 最近写入 observation 的索引
    /// @param blockTimestamp 新 observation 的时间戳
    /// @param tick 上一条 observation 至本次写入期间生效的 active tick
    /// @param liquidity 上一条 observation 至本次写入期间生效的池内活跃流动性
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

        // 只有走到旧容量尾部才启用新容量，避免中途改变取模基数后打乱环形数组的时间顺序。
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        // 使用过去这段时间内的 tick 和 liquidity，把上一条累计值推进到当前区块时间。
        self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
    }

    /// @notice 预先准备最多可保存 `next` 条 observation 的存储槽
    /// @dev 扩容只预热存储，不会凭空生成历史数据，也不会立即改变 cardinality。
    /// 例如当前只能保存 2 条记录，用户请求扩到 10：grow() 会预热索引 2 至 9 并返回 10，
    /// 但池仍然只有原来的 2 条有效 observation。后续池操作每写一条，才逐步形成更长的可查询历史。
    ///
    /// blockTimestamp 预写为 1，是把槽位从全零状态改为非零状态，使扩容调用者提前支付昂贵的首次
    /// SSTORE 成本。initialized 保持 false，所以时间戳 1 只是 gas 优化占位符，不会参与预言机计算。
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
        // 预热新槽位；后续 transform() 写入真实数据时才会把 initialized 设为 true。
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice 比较两个 uint32 时间戳的先后顺序
    /// @dev 支持零次或一次回绕；按真实时间顺序，a 和 b 都必须不晚于 time
    ///
    /// 回绕例子：真实时间线依次经过 2^32 - 5、2^32 - 1、2^32 + 3，但保存为 uint32 后分别是
    /// 2^32 - 5、2^32 - 1、3。若当前 time=3，数值 3 看似小于旧时间戳；本函数会给位于回绕前且
    /// 大于 time 的时间戳保留原值，并给回绕后且不大于 time 的时间戳加 2^32，再按真实时间线比较。
    /// @param time 截断为 32 位的当前时间戳
    /// @param a 待比较的时间戳
    /// @param b 待比较的时间戳
    /// @return bool 按时间顺序 a 是否早于或等于 b
    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // a、b 都位于当前 uint32 周期内时，普通数值大小就是时间先后顺序。
        if (a <= time && b <= time) return a <= b;

        // 若某时间戳大于当前 time，视为位于回绕前；否则视为位于回绕后并加上一个完整周期。
        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice 查找包围目标时间的两条 observation，即 beforeOrAt <= target <= atOrAfter
    /// @dev 结果可能是同一条或相邻两条 observation。目标必须位于最旧和最新已存历史之间。
    /// 环形数组按物理索引可能不连续，因此使用扩展逻辑索引进行二分，再通过取模读取实际槽位。
    ///
    /// 例如容量为 5、最新 index=1，物理数组中的时间顺序可能是索引 2、3、4、0、1。
    /// 此时 l=(1+1)%5=2，r=2+5-1=6，逻辑索引 2..6 单调递增；读取时再对 5 取模，
    /// 就会依次映射回物理索引 2、3、4、0、1，从而仍可使用 O(log n) 二分查找。
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
        uint256 l = (index + 1) % cardinality; // 把最新元素的下一格视为最旧元素候选。
        uint256 r = l + cardinality - 1; // 扩展到不回绕的逻辑区间，末端对应最新元素。
        uint256 i;
        while (true) {
            // 在逻辑时间有序区间中取中点
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // 数组尚未写满时，最旧元素候选可能只是 grow() 预热槽；真实数据位于逻辑右侧。
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
    /// 查询分为三种业务情况：
    /// 1. target 等于最新快照时间：直接返回该快照；
    /// 2. target 晚于最新快照：说明期间没有触发落盘，用当前 tick/liquidity 从最新快照推演；
    /// 3. target 位于已保存历史中：检查最旧边界后，通过 binarySearch 找到左右相邻快照。
    ///
    /// 例如最新快照在 12:00，当前时间 12:10，期间池没有交易。查询 12:05 时不能返回 12:00 的旧值，
    /// 而要假设当前 tick 和 liquidity 在这 5 分钟保持有效，用 transform() 计算 12:05 的反事实快照。
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

        // 常见快速路径：latestTime <= target <= currentTime。
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // 最新 observation 恰好位于目标时刻，无需提供右侧 observation
                return (beforeOrAt, atOrAfter);
            } else {
                // 池在 latest 到 target 之间没有落盘，使用这段时间持续生效的当前状态推演。
                return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity));
            }
        }

        // 环形数组已写满时 index+1 是最旧记录；未写满时该位置可能尚未初始化，应回退到索引 0。
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // 例如最旧记录是 1 小时前，则无法回答 2 小时前的累计值，调用会以 OLD 回退。
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // 目标位于已存历史内部，二分查找最接近的前后 observation
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @notice 返回指定回溯时刻的 tick 和每单位流动性秒数累计值
    /// @dev 若目标早于最旧 observation 则回退。secondsAgo 为 0 时返回当前累计值。
    /// 若目标落在两条 observation 之间，则按时间比例线性插值得到目标时刻的反事实累计值。
    ///
    /// 本函数返回累计值而不是平均值。典型 TWAP 查询会分别读取 secondsAgo=1800 和 secondsAgo=0，
    /// 再计算 (当前 tickCumulative - 30 分钟前 tickCumulative) / 1800，得到过去 30 分钟平均 tick。
    /// periphery 的 OracleLibrary.consult() 正是按这一方式工作，并对负数除法做向负无穷方向取整。
    ///
    /// 插值例子：已保存的两条 observation 位于第 100 秒和第 160 秒，其 tickCumulative 分别为
    /// 10000 和 22000。查询第 130 秒时，targetDelta / observationTimeDelta = 30 / 60，
    /// 所以目标累计值为 10000 + (22000 - 10000) / 60 * 30 = 16000。
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
        // secondsAgo=0 是最常见的“读取现在”。若当前秒尚未落盘，只在内存中推演，不修改存储。
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        uint32 target = time - secondsAgo;

        // 找到 beforeOrAt.blockTimestamp <= target <= atOrAfter.blockTimestamp。
        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, liquidity, cardinality);

        if (target == beforeOrAt.blockTimestamp) {
            // 目标正好命中左侧 observation
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // 目标正好命中右侧 observation
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // 目标位于两条 observation 中间，累计函数在该区间内按固定 tick/liquidity 线性增长。
            // 左右两条 observation 之间的总秒数。
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            // 目标距离左侧 observation 的秒数。
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            // tick 累计值先除后乘，保持与原始实现一致；secondsPerLiquidity 使用 uint256 中间值避免乘法溢出。
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
    ///
    /// 业务例子：传入 [3600, 0] 可一次获得“一小时前”和“现在”的两组累计值，调用方用两者做差即可
    /// 计算一小时 TWAP。也可传入 [86400, 3600, 0] 获取多个时间锚点，用于比较日均价格和小时均价。
    /// 数组顺序会原样保留，每个 secondsAgos[i] 的结果写入返回数组的同一索引 i。
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
