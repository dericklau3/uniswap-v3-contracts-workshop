// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';

/// @title 计算单个 tick 区间内的交换结果
/// @notice 在当前流动性保持不变的价格区间内，计算一步交换后的价格、输入、输出和手续费
/// @dev `UniswapV3Pool.swap` 会把一次用户订单拆成很多个 step，本库只负责其中一步。
/// 一步的业务边界是“当前活跃流动性不变”：只要价格还没跨过下一个已初始化 tick，
/// 池子里的可用 liquidity 就固定，可以用 `SqrtPriceMath` 按恒定乘积曲线计算价格移动。
///
/// 本步的目标价格通常是下一个已初始化 tick 对应的价格，也可能是用户设置的价格限制。
/// 若剩余数量足够，就移动到目标并把跨 tick、更新 liquidity 的工作交还给 Pool；
/// 若剩余数量不够，就在当前区间内停下，表示这笔 swap 已经成交完或触碰用户预算。
///
/// 精确输入先从预算中预留手续费，再用净输入推动价格；精确输出先判断到达目标最多能给多少输出，
/// 不够时移动到目标，足够时只移动到刚好满足输出的位置。这样可以同时支持“我最多卖多少”和
/// “我一定要买到多少”两种常见交易意图。
library SwapMath {
    /// @notice 根据本步交换参数计算区间内的执行结果
    /// @dev amountRemaining 为正表示精确输入，为负表示精确输出。精确输入时，amountIn 与 feeAmount 之和
    /// 不会超过剩余输入。本函数只处理当前 tick 区间；到达目标价格后由池继续跨 tick 并更新流动性。
    ///
    /// 输出的 `amountIn` / `amountOut` 都是不带符号的“本步数量”，具体是哪种 token 由方向决定：
    /// - zeroForOne 时，输入是 token0，输出是 token1；
    /// - oneForZero 时，输入是 token1，输出是 token0。
    /// Pool 会在外层把这些无符号数量转换成最终的 amount0/amount1 符号约定。
    /// @param sqrtRatioCurrentX96 池当前平方根价格，Q64.96 格式
    /// @param sqrtRatioTargetX96 本步不可越过的目标价格，价格方向同时决定交换方向
    /// @param liquidity 当前 tick 区间内可用的活跃流动性
    /// @param amountRemaining 尚待交换的输入量或输出量；正数是剩余输入预算，负数是剩余输出需求
    /// @param feePips 从输入资产收取的费率，单位为百万分之一，例如 3000 表示 0.3%
    /// @return sqrtRatioNextX96 本步结束后的平方根价格，不会越过目标价格
    /// @return amountIn 本步实际使用的 token0 或 token1 输入量，不含手续费
    /// @return amountOut 本步实际得到的 token0 或 token1 输出量
    /// @return feeAmount 从输入资产中收取的手续费
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    )
        internal
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        // 当前价格高于目标价格表示价格要向下走，也就是 zeroForOne：
        // 用户把 token0 输入池子、从池子拿走 token1，池中 token0/token1 比例升高，价格下降。
        // 反过来，目标价格高于当前价格表示 oneForZero：用户输入 token1，价格上升。
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;

        // amountRemaining 的符号表达用户意图：
        // - 正数：精确输入，用户给定最多可花的输入 token；
        // - 负数：精确输出，用户给定想拿到的输出 token，外层会反向计算需要多少输入。
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
            // 精确输入：先按费率从总预算中分离净输入，再判断净输入是否足以把价格推到目标。
            // 例如 0.3% 费率下，用户给 1000 单位预算，最多有 997 单位参与曲线交换，约 3 单位作为费用。
            // 这里向下取整，确保“净输入 + 手续费”不会超过用户在本步剩余的输入预算。
            uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);

            // 根据交换方向计算“从当前价格完整走到目标价格”需要的净输入量。
            // zeroForOne 时需要 token0 输入推动价格下行；oneForZero 时需要 token1 输入推动价格上行。
            // `roundUp=true` 是为了保证输入数量足够到达目标，不会因为除法截断而少付一点点。
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);

            // 净输入足够时直接到达 tick 边界或用户价格限制；
            // 净输入不够时，全部净输入都在当前区间成交，并反推出成交后的中间价格。
            if (amountRemainingLessFee >= amountIn) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
        } else {
            // 精确输出：先计算如果完整走到目标价格，本区间最多能给出多少输出 token。
            // zeroForOne 时输出 token1；oneForZero 时输出 token0。
            // `roundUp=false` 是为了避免高估用户能拿到的输出，保证池子不会多付。
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);

            // 用户还需要的输出数量足以吃完整个区间时，价格走到目标；
            // 否则只移动到“刚好给够本步剩余输出需求”的价格，swap 可以在当前区间结束。
            if (uint256(-amountRemaining) >= amountOut) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
        }

        // 是否已经完整走到本步目标价格。
        // max=true：本区间被完整吃穿，外层 Pool 可能需要跨 tick 并进入下一个流动性区间。
        // max=false：价格停在区间中间，说明用户的输入预算或输出需求已经在本区间内完成。
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

        // 根据实际起止价格重新计算本步输入和输出。
        // 前面预估的 amountIn/amountOut 只描述“完整走到目标”的数量；
        // 如果没有到达目标，就必须按实际结束价格重新算一次，得到真实成交数量。
        if (zeroForOne) {
            // token0 输入、token1 输出：价格从高到低，因此 delta 参数顺序是 next -> current。
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false);
        } else {
            // token1 输入、token0 输出：价格从低到高，因此 delta 参数顺序是 current -> next。
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        }

        // 精确输出模式下，舍入误差不能让实际输出超过用户剩余需要的数量。
        // 即使底层价格公式因为取整多算了 1 wei 输出，也要截回用户请求的数量，避免池子超额支付。
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // 计算兑换手续费。
        // 手续费始终从输入资产中收取，所以 Pool 外层会把 feeAmount 和 amountIn 一起计入用户应付输入。
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // 精确输入且未到达目标价格，说明用户本步剩余预算已经全部被用完。
            // 由于前面先把预算拆成“净输入”和“手续费”，这里用总预算减真实输入，剩余部分就是手续费。
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // 其他情况需要根据真实输入反推手续费：
            // amountIn 是扣费后的净输入，feePips 是总输入中的费率，
            // 因此手续费 = amountIn * fee / (1 - fee)，并向上取整，保证 LP/协议不会少收。
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
