// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Pool.sol';

import './NoDelegateCall.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SafeCast.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/Position.sol';
import './libraries/Oracle.sol';

import './libraries/FullMath.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/SwapMath.sol';

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';

/// @title Uniswap V3 单一交易对的核心池
/// @notice 管理一个 `(token0, token1, fee)` 市场中的价格、流动性、手续费和历史观察值。
/// @dev 教学上可以把本合约拆成四本相互配合的账：
/// 1. 价格账：`slot0` 保存当前平方根价格和 tick，`swap` 沿 tick 网格推动价格；
/// 2. 流动性账：`ticks` 记录跨越边界时应增减多少活跃流动性，`positions` 记录每位 LP 的区间份额；
/// 3. 手续费账：全局手续费增长按“每单位活跃流动性”累计，仓位通过区间快照结算自己的收益；
/// 4. 时间账：`observations` 对 tick 和流动性按时间积分，为 TWAP 等外部风控提供历史依据。
///
/// 典型业务调用链：
/// - 建池：Factory 部署池 -> `initialize` 设置首个价格；
/// - 做市：PositionManager -> `mint` -> mint callback 付款；
/// - 交易：Router -> `swap` -> swap callback 付款；
/// - 退出：`burn` 先把本金记为待领取 -> `collect` 再转出本金与手续费；
/// - 闪电贷：`flash` 先转出资产 -> callback 执行业务 -> 本交易内归还本金和费用。
///
/// Core 池故意不主动从用户账户 `transferFrom`。它先计算应收金额并回调调用者，再用余额差确认付款，
/// 因而 Router、PositionManager 或套利合约可以在回调中自由组织付款来源，同时池仍能保证最终偿付。
contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];

    /// @notice 创建该池子的工厂合约地址。
    address public immutable override factory;
    /// @notice 池子中的第一个代币，按地址从小到大排序。
    address public immutable override token0;
    /// @notice 池子中的第二个代币，按地址从小到大排序。
    address public immutable override token1;
    /// @notice 每笔 swap 收取的手续费，单位是百万分之一。
    uint24 public immutable override fee;

    /// @notice 可用 tick 之间的间隔，间隔越大代表价格刻度越粗。
    int24 public immutable override tickSpacing;

    /// @notice 单个 tick 能承载的最大流动性，用来避免 tick 级别溢出。
    uint128 public immutable override maxLiquidityPerTick;

    struct Slot0 {
        // 当前价格的平方根，使用 Q64.96 定点数表示。
        uint160 sqrtPriceX96;
        // 当前价格对应的 tick。
        int24 tick;
        // oracle observations 数组中最近一次写入的位置。
        uint16 observationIndex;
        // 当前实际保存的 oracle 观察点数量上限。
        uint16 observationCardinality;
        // 目标观察点数量上限，会在后续 observations.write 中逐步扩容。
        uint16 observationCardinalityNext;
        // 协议手续费分成比例：低 4 位给 token0，高 4 位给 token1，数值表示从 LP 手续费中抽取 1/x。
        uint8 feeProtocol;
        // 重入锁；false 表示池子正在执行敏感流程。
        bool unlocked;
    }
    /// @notice 池子的核心状态，打包存储价格、tick、oracle 容量、协议费和锁状态。
    Slot0 public override slot0;

    /// @notice token0 手续费的全局累计增长，按每份流动性计价，Q128.128 表示。
    uint256 public override feeGrowthGlobal0X128;
    /// @notice token1 手续费的全局累计增长，按每份流动性计价，Q128.128 表示。
    uint256 public override feeGrowthGlobal1X128;

    // 已累积但尚未提取的协议手续费，单位分别是 token0/token1 本身。
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    /// @notice 工厂 owner 可提取的协议手续费余额。
    ProtocolFees public override protocolFees;

    /// @notice 当前价格区间内正在参与成交的总流动性。
    uint128 public override liquidity;

    /// @notice 每个已初始化 tick 的边界信息，记录流动性变化和手续费快照。
    mapping(int24 => Tick.Info) public override ticks;
    /// @notice tick 初始化位图，用于 swap 时快速寻找下一个有流动性变化的 tick。
    mapping(int16 => uint256) public override tickBitmap;
    /// @notice LP 仓位信息，key 由 owner、tickLower、tickUpper 共同确定。
    mapping(bytes32 => Position.Info) public override positions;
    /// @notice TWAP oracle 观察点环形数组，记录历史 tick 和每份流动性秒数。
    Oracle.Observation[65535] public override observations;

    /// @dev 池子的互斥重入保护，也阻止未初始化池子执行需要价格状态的函数。
    /// mint、swap、flash 都通过回调收款，最终用余额差校验是否付款成功，因此这些流程必须被锁保护。
    modifier lock() {
        require(slot0.unlocked, 'LOK');
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    /// @dev 只允许工厂合约 owner 执行，用于协议费配置和提取这类治理操作。
    modifier onlyFactoryOwner() {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        _;
    }

    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    /// @dev 校验 LP 仓位的上下 tick：下界必须小于上界，且不能越过协议允许的最小/最大 tick。
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    /// @dev 返回截断为 32 位的区块时间戳，等价于对 2**32 取模；测试合约会重写它来模拟时间。
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // 有意截断，oracle 使用 32 位时间戳并依靠溢出规则工作。
    }

    /// @dev 读取池子持有的 token0 余额；使用底层 staticcall 是为了省掉多余的 extcodesize 检查。
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev 读取池子持有的 token1 余额；使用底层 staticcall 是为了省掉多余的 extcodesize 检查。
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @notice 返回某个仓位区间内部的累计 tick、每份流动性累计秒数和经过秒数快照。
    /// @dev LP 可用它对比两次快照，计算该价格区间内随时间变化的平均价格和流动性占用情况。
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        noDelegateCall
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }

        Slot0 memory _slot0 = slot0;

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) =
                observations.observeSingle(
                    time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    liquidity,
                    _slot0.observationCardinality
                );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 -
                    secondsPerLiquidityOutsideLowerX128 -
                    secondsPerLiquidityOutsideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    /// @notice 按 secondsAgos 查询 oracle 累计值，用于计算 TWAP 和时间加权流动性。
    /// @param secondsAgos 每个查询点距离当前区块时间的秒数，例如 [3600, 0] 表示一小时前和现在。
    /// @return tickCumulatives 各时间点的累计 tick。
    /// @return secondsPerLiquidityCumulativeX128s 各时间点的每份流动性累计秒数。
    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );
    }

    /// @notice 提高 oracle 观察点容量目标，让池子能保存更长的价格历史。
    /// @dev 只设置目标容量，真正扩容在后续写入 observation 时发生，避免一次性写太多存储。
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external
        override
        lock
        noDelegateCall
    {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // 事件需要记录旧值。
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    /// @notice 初始化池子的初始价格，只能执行一次。
    /// @dev 新池部署后还不能交易或添加流动性，因为 `slot0.sqrtPriceX96` 默认为 0。
    /// 首个调用者根据市场价格传入 `sqrt(price(token1/token0)) * 2^96`，合约再反推出对应 tick。
    /// 初始化同时写入第一条 oracle 快照，并把 `unlocked` 设为 true。这里不使用 `lock`，
    /// 正是因为初始化前锁的默认值为 false，而本函数负责完成从“未启用”到“可使用”的状态切换。
    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    struct ModifyPositionParams {
        // 仓位所有者地址。
        address owner;
        // 仓位价格区间的下界和上界 tick。
        int24 tickLower;
        int24 tickUpper;
        // 本次要增加或减少的流动性，正数为加仓，负数为减仓。
        int128 liquidityDelta;
    }

    /// @dev 修改一个 LP 仓位，并根据当前价格判断这次增减流动性需要结算哪些代币。
    ///
    /// 业务上可以把本函数理解为“修改仓位的总调度器”，它完成两件事：
    /// 1. 调用 `_updatePosition` 更新仓位账本、上下边界 tick、tick 位图以及手续费；
    /// 2. 根据当前价格相对于 `[tickLower, tickUpper)` 的位置，计算本次加仓或减仓对应的 token0/token1。
    ///
    /// `liquidityDelta > 0` 表示增加流动性，此时返回的 amount 通常为正，代表用户需要向池子支付代币；
    /// `liquidityDelta < 0` 表示减少流动性，此时返回的 amount 通常为负，代表池子欠用户代币；
    /// `liquidityDelta == 0` 不改变流动性，仅用于把最新手续费增长结算进仓位的 tokensOwed。
    ///
    /// 集中流动性的代币构成取决于当前价格：
    /// - 当前 tick 在区间下方：仓位全部由 token0 构成；
    /// - 当前 tick 在区间内部：仓位同时由 token0 和 token1 构成，并属于池子的活跃流动性；
    /// - 当前 tick 在区间上方：仓位全部由 token1 构成。
    /// @param params 仓位所有者、价格区间和流动性变化量。
    /// @return position 指向该 owner + tick 区间仓位的存储引用。
    /// @return amount0 池子应收的 token0 数量；为负数时表示池子应付给用户。
    /// @return amount1 池子应收的 token1 数量；为负数时表示池子应付给用户。
    function _modifyPosition(ModifyPositionParams memory params)
        private
        noDelegateCall
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        // 仓位区间必须满足 tickLower < tickUpper，且两个边界都在 TickMath 允许的范围内。
        // 注意：这里仅检查 tick 的数学范围；tickSpacing 的整倍数约束由 Tick.update 间接使用的调用约定保证。
        checkTicks(params.tickLower, params.tickUpper);

        // slot0 集中保存当前价格、当前 tick 和 oracle 索引等高频状态。
        // 先复制到 memory，后续多次读取都从内存完成，可以减少昂贵的 SLOAD。
        Slot0 memory _slot0 = slot0; // 缓存 slot0，减少重复 SLOAD。

        // 先更新“会计状态”，再计算本次应转移的代币：
        // - 更新 owner 在该价格区间内的 Position.Info；
        // - 把旧流动性截至当前时刻赚取的手续费记入 tokensOwed；
        // - 更新上下边界 tick 的总流动性、净流动性和位图。
        //
        // 即使 liquidityDelta == 0 也需要调用，因为 burn(..., amount = 0) 会利用这条路径只结算手续费。
        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        // 根据流动性变化和当前价格位置，计算用户需要付入或应收回的 token0/token1。
        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // 情况一：当前价格位于区间下方。
                //
                // token0 是价格上升时逐步被卖出的资产。当前价格尚未进入该区间，
                // 因而整段 `[tickLower, tickUpper)` 的流动性都以 token0 形式等待成交，不需要 token1。
                // 计算上下边界之间完整价格跨度所对应的 token0 数量。
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );

            } else if (_slot0.tick < params.tickUpper) {
                // 情况二：当前价格位于 `[tickLower, tickUpper)` 内。
                //
                // 该仓位会立即参与交易，因此它既影响用户自己的 Position.Info，
                // 也会改变池子当前正在使用的全局活跃流动性 `liquidity`。
                //
                // 当前价格把仓位区间分为两段：
                // - `[当前价格, tickUpper)` 尚未成交，对应 token0；
                // - `[tickLower, 当前价格)` 已经转换为 token1，对应 token1。
                uint128 liquidityBefore = liquidity; // 缓存当前活跃流动性，减少重复 SLOAD。

                // oracle 的 secondsPerLiquidity 累计值依赖“当时的活跃流动性”。
                // 因此必须先用 liquidityBefore 写入截至当前区块时间的观察值，
                // 再修改全局 liquidity；否则过去这一段时间会被错误地按新流动性计算。
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                // 当前价格到上边界之间的未成交部分，以 token0 表示。
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                // 下边界到当前价格之间的已成交部分，以 token1 表示。
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                // 只有当前价格位于仓位区间内时，这份仓位才是“活跃流动性”。
                // 加仓时增加全局 liquidity，减仓时减少；区间外仓位不会走到这里。
                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // 情况三：当前价格位于区间上方。
                //
                // 价格已经从左向右穿过整个仓位区间，原本的 token0 已全部转换为 token1，
                // 所以只需计算完整区间对应的 token1 数量，不需要 token0。
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    /// @dev 读取并更新指定仓位，包括 tick 边界、位图、区间手续费快照和仓位本身。
    ///
    /// 本函数只处理“仓位会计”，不计算用户实际要支付或取回多少 token。核心顺序如下：
    /// 1. 找到由 `(owner, tickLower, tickUpper)` 唯一确定的仓位；
    /// 2. 若流动性发生变化，更新上下边界 tick 及 tickBitmap；
    /// 3. 根据全局手续费增长和两个边界保存的 outside 值，计算区间内部手续费增长；
    /// 4. 先按仓位原有流动性结算历史手续费，再应用 liquidityDelta；
    /// 5. 减仓后若某个边界已无任何仓位使用，则清理该 tick 的存储。
    ///
    /// 为什么需要同时维护 Position 和 Tick：
    /// - Position 记录“某个用户在某个区间拥有多少流动性、赚了多少手续费”；
    /// - Tick 记录“价格跨过这个边界时，池子的活跃流动性应该变化多少”；
    /// - tickBitmap 标记哪些 tick 已初始化，供 swap 快速寻找下一个流动性边界。
    /// @param owner 仓位所有者。
    /// @param tickLower 仓位区间下界 tick。
    /// @param tickUpper 仓位区间上界 tick。
    /// @param liquidityDelta 本次流动性变化量：正数加仓、负数减仓、零表示仅结算手续费。
    /// @param tick 当前 tick，作为参数传入以减少重复读取 slot0。
    /// @return position 更新后的仓位存储引用。
    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {

        // Core 层没有 NFT tokenId。一个仓位由 owner 与上下边界共同唯一标识：
        // positionKey = keccak256(owner, tickLower, tickUpper)。
        // 同一 owner 对同一区间多次加仓，会累计到同一个 Position.Info。
        position = positions.get(owner, tickLower, tickUpper);

        // 全局手续费增长表示池子自创建以来，每单位活跃流动性累计获得的手续费，采用 Q128 定点数。
        // 缓存后既用于初始化 tick 的 outside 快照，也用于计算该仓位区间内部的手续费增长。
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // 缓存全局 token0 手续费增长。
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // 缓存全局 token1 手续费增长。

        // flipped 表示 tick 的初始化状态是否发生了变化：
        // - 首份引用该边界的流动性被添加：未初始化 -> 已初始化；
        // - 最后一份引用该边界的流动性被移除：已初始化 -> 未初始化。
        // 只有发生这种切换时，才需要翻转 tickBitmap 中对应的 bit。
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            uint32 time = _blockTimestamp();

            // Tick 首次初始化时，需要保存手续费和 oracle 累计值的 outside 基准。
            // observeSingle(secondsAgo = 0) 将最后一个已写 observation 推算到当前时间，
            // 得到“此刻”的 tick 累计值与每单位流动性时间累计值。
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) =
                observations.observeSingle(
                    time,
                    0,
                    slot0.tick,
                    slot0.observationIndex,
                    liquidity,
                    slot0.observationCardinality
                );

            // 更新下边界 tick：
            // - liquidityGross：所有把该 tick 当作边界的仓位流动性绝对总量；
            // - liquidityNet：价格从左向右跨过该下边界时，应加入全局活跃流动性的净值。
            //
            // upper = false，因此 liquidityNet += liquidityDelta。
            // 例如加仓 100 后，从左向右跨过 tickLower 时，池子的活跃流动性增加 100。
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );

            // 更新上边界 tick。
            // upper = true，因此 liquidityNet -= liquidityDelta。
            // 例如加仓 100 后，从左向右跨过 tickUpper 时，池子的活跃流动性减少 100，
            // 表示该仓位已经离开其做市区间，不再参与当前价格附近的交易。
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true,
                maxLiquidityPerTick
            );

            // tickBitmap 是“已初始化 tick”的稀疏索引。
            // swap 不必逐个扫描所有 tick，而是通过位运算快速找到下一个有流动性变化的边界。
            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        // 每个 tick 只保存其一侧的 feeGrowthOutside，而不是为每个仓位单独累计手续费。
        // getFeeGrowthInside 根据当前 tick 所在位置，把全局手续费拆成：
        // “下边界以下 + 仓位区间内部 + 上边界以上”，再取出中间的区间内部增长。
        //
        // 这一步在 liquidityDelta == 0 时同样执行，所以可以不改变流动性而单独刷新手续费。
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);

        // Position.update 的结算顺序非常关键：
        // 1. 用“当前区间手续费增长 - 上次快照”乘以“修改前的仓位流动性”，算出历史手续费；
        // 2. 把历史手续费加入 tokensOwed0/tokensOwed1；
        // 3. 更新手续费快照；
        // 4. 最后把 liquidityDelta 应用到仓位流动性。
        //
        // 因此本次新增加的流动性不会分享加仓之前产生的手续费；
        // 本次移除的流动性也能先拿到减仓之前应得的全部手续费。
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);


        // 只有减仓才可能让 liquidityGross 归零。
        // ticks.update 必须先使用旧 tick 数据完成手续费计算，因此不能提前 delete；
        // 等 position.update 完成结算后，再清除已无人使用的边界状态。
        //
        // tickBitmap 已在上方同步翻转，后续 swap 不会再把被清理的 tick 当作有效边界。
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    /// @notice 给指定价格区间添加流动性，调用者必须在回调中把所需 token 支付给池子。
    /// @dev 业务流程是“先记账、后收款、最后验账”：
    /// 1. `_modifyPosition` 更新仓位和 tick，并算出当前价格下应投入多少 token0/token1；
    /// 2. 池记录回调前余额，调用调用者的 `uniswapV3MintCallback`；
    /// 3. 常见调用者 PositionManager 从真正的 payer 账户把代币转给池；
    /// 4. 池比较回调前后余额，任何少付都会使整笔交易回退，前面的记账也随之撤销。
    /// `recipient` 是 core 仓位所有者，不一定等于付款人；外围合约正是利用这一点代用户管理 NFT 仓位。
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        (, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(amount).toInt128()
                })
            );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        // 常见调用者是 NonfungiblePositionManager；它会在回调中代 LP 支付 token0/token1。
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @notice 提取调用者仓位中已经累计的 token0/token1，包括手续费和 burn 后待领取的本金。
    /// @dev `collect` 只提取已经记入 `tokensOwed` 的余额，不会主动刷新手续费。
    /// 因此外围 PositionManager 通常会先执行一次 `burn(..., amount=0)`，把最新手续费结算到账，
    /// 再调用 `collect`。这里不重新校验 tick，因为非法区间不可能形成带非零余额的合法仓位。
    /// 用户可以只领取一部分，未领取部分继续保存在仓位账本中。
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    /// @notice 从调用者仓位中移除流动性，并把可领取的 token 记入 tokensOwed。
    /// @dev `burn` 的名字容易让初学者误以为它会立即把代币打回用户，实际这里只做会计结算：
    /// 移除的流动性按当前价格换算为 token0/token1，并累加到 `tokensOwed`；真正转账由后续 `collect` 完成。
    /// 将“减仓记账”和“资金转出”分开，可以让用户合并领取本金与手续费，也允许只领取部分资产。
    /// 当 `amount=0` 时不会减仓，但仍会刷新该仓位截至当前的手续费，这是常见的手续费结算技巧。
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(amount).toInt128()
                })
            );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    struct SwapCache {
        // 当前输入代币方向上的协议费分母；0 表示不开启协议费。
        uint8 feeProtocol;
        // swap 开始时的活跃流动性，写 oracle 时需要用起点快照。
        uint128 liquidityStart;
        // 当前区块时间戳，整个 swap 过程复用同一个值。
        uint32 blockTimestamp;
        // 当前累计 tick，只有跨过已初始化 tick 时才计算，避免无谓 oracle 读取。
        int56 tickCumulative;
        // 当前每份流动性累计秒数，同样按需计算。
        uint160 secondsPerLiquidityCumulativeX128;
        // 标记上面两个 oracle 累计值是否已经在本次 swap 中缓存。
        bool computedLatestObservation;
    }

    // swap 的顶层运行状态，循环结束后一次性写回存储。
    struct SwapState {
        // 还需要兑换的数量；精确输入时递减到 0，精确输出时递增到 0。
        int256 amountSpecifiedRemaining;
        // 已经计算出的另一侧数量；精确输入时是负的输出量，精确输出时是正的输入量。
        int256 amountCalculated;
        // 当前步骤后的价格平方根。
        uint160 sqrtPriceX96;
        // 当前价格对应的 tick。
        int24 tick;
        // 输入代币方向的全局手续费增长。
        uint256 feeGrowthGlobalX128;
        // 本次 swap 累计给协议的输入代币手续费。
        uint128 protocolFee;
        // 当前价格所在区间的活跃流动性。
        uint128 liquidity;
    }

    struct StepComputations {
        // 本轮 step 开始时的价格。
        uint160 sqrtPriceStartX96;
        // 沿 swap 方向找到的下一个已初始化 tick，或当前 word 内边界。
        int24 tickNext;
        // tickNext 是否真的是已初始化 tick。
        bool initialized;
        // tickNext 对应的价格平方根。
        uint160 sqrtPriceNextX96;
        // 本轮 step 消耗的输入代币数量。
        uint256 amountIn;
        // 本轮 step 产出的输出代币数量。
        uint256 amountOut;
        // 本轮 step 支付的 swap 手续费。
        uint256 feeAmount;
    }

    /// @notice 在池子内执行 swap。
    /// @dev `zeroForOne=true` 表示卖 token0 买 token1，价格会向较小 tick 移动；
    /// `zeroForOne=false` 表示卖 token1 买 token0，价格会向较大 tick 移动。
    /// `amountSpecified > 0` 是精确输入，用户锁定最多卖多少；小于 0 是精确输出，用户锁定必须买到多少。
    ///
    /// swap 不是一次公式计算到底，而是循环经过若干价格区间。每轮会比较四个停止条件：
    /// 当前价格、下一个已初始化 tick、用户价格限制、剩余待成交数量。到达 tick 后应用 `liquidityNet`，
    /// 因为有些 LP 仓位从该处开始生效，另一些从该处停止生效；随后用新的活跃流动性继续下一轮。
    ///
    /// 资金采用“先给输出、回调收输入”的模式。池先把输出 token 转给 recipient，再回调调用者付款，
    /// 最后检查输入 token 余额至少增加了应付数量。任一环节失败，EVM 会把价格、转账和全部中间状态回退。
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS');

        Slot0 memory slot0Start = slot0;

        require(slot0Start.unlocked, 'LOK');
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        slot0.unlocked = false;

        // 缓存 swap 起点信息，跨 tick 和写 oracle 时需要这些快照。
        SwapCache memory cache =
            SwapCache({
                liquidityStart: liquidity,
                blockTimestamp: _blockTimestamp(),
                feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
                secondsPerLiquidityCumulativeX128: 0,
                tickCumulative: 0,
                computedLatestObservation: false
            });

        bool exactInput = amountSpecified > 0;

        // 初始化 swap 运行状态：剩余数量、当前价格、费用增长和活跃流动性都先在内存里更新。
        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
                protocolFee: 0,
                liquidity: cache.liquidityStart
            });

        // 只要用户指定的数量还没完成，且价格还没触碰限制，就继续推进价格。
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // 在 tick 位图里找下一个流动性边界。价格跨过边界时，活跃流动性会按 liquidityNet 增减。
            // zeroForOne 为 true 时价格向左移动，常见业务含义是用 token0 换 token1。
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne
            );

            // tick 位图本身不知道全局最小/最大 tick，这里避免搜索结果越界。
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // 把下一个 tick 转成价格，作为本轮 step 的候选终点。
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // 计算本轮能推进到哪里：下一个 tick、用户价格限制，或数量刚好耗尽的位置。
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            // 更新剩余待兑换数量和已计算出的另一侧数量；符号约定跟最终 amount0/amount1 保持一致。
            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // 如果开启了协议费，先从 LP 手续费中切出协议分成，再把剩余部分计给 LP。
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // 按每份活跃流动性累计本轮 LP 手续费。
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);

            // 如果价格刚好到达下一个 tick，需要处理流动性边界穿越。
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // 已初始化 tick 才代表真实仓位边界，需要更新手续费外侧快照并取出 liquidityNet。
                if (step.initialized) {
                    // 第一次跨已初始化 tick 时才读取 oracle 累计值，后续复用，节省 gas。
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet =
                        ticks.cross(
                            step.tickNext,
                            (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                            (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                            cache.secondsPerLiquidityCumulativeX128,
                            cache.tickCumulative,
                            cache.blockTimestamp
                        );
                    // 向左跨 tick 时，需要反向理解 liquidityNet；该值不可能是 int128 最小值，所以取负安全。
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // 没有刚好跨 tick，但价格移动了，则根据新价格重新计算 tick。
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // 如果 tick 变化，写入 oracle 并更新 slot0 的价格、tick 和 observation 指针。
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) =
                observations.write(
                    slot0Start.observationIndex,
                    cache.blockTimestamp,
                    slot0Start.tick,
                    cache.liquidityStart,
                    slot0Start.observationCardinality,
                    slot0Start.observationCardinalityNext
                );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            // tick 未变化时，只需要更新价格。
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // 跨 tick 后活跃流动性可能变化，最后统一写回。
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        // 写回全局 LP 手续费和协议费。全局手续费允许溢出；协议费需要在 uint128 满之前提取。
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        // 按 Uniswap 约定，正数表示池子应收，负数表示池子应付。
        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // 先把输出代币转给用户，再通过回调收输入代币，最后用余额差确认用户已付款。
        if (zeroForOne) {
            // token0 -> token1：amount1 为负时，池子向用户发送 token1。
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));

            // 回调收取 token0 输入。
            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance0Before.add(uint256(amount0)) <= balance0(), 'IIA');
        } else {
            // token1 -> token0：amount0 为负时，池子向用户发送 token0。
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));

            // 回调收取 token1 输入。
            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), 'IIA');
        }

        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true;
    }

    /// @notice 闪电借出 token0/token1，调用者必须在回调中归还本金和手续费。
    /// @dev 手续费按池子费率计算，归还后分配给 LP，并按协议费设置切出协议分成。
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override lock noDelegateCall {
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, 'L');

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        // 前面的 require 已确认 balanceAfter 至少比 balanceBefore 多 fee，因此这里相减安全。
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) protocolFees.token0 += uint128(fees0);
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) protocolFees.token1 += uint128(fees1);
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    /// @notice 设置 token0/token1 方向的协议手续费分成比例。
    /// @dev 只有工厂 owner 可调用；非零值必须在 4 到 10 之间，表示抽取 LP 手续费的 1/x。
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
                (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    /// @notice 提取已累积的协议手续费。
    /// @dev 如果请求提走全部余额，会刻意留下 1 wei，避免清空存储槽导致后续 gas 成本变高。
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFees.token0) amount0--; // 留 1 wei，避免清空 storage slot。
            protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFees.token1) amount1--; // 留 1 wei，避免清空 storage slot。
            protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
