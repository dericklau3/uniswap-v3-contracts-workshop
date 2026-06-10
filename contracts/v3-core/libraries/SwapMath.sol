// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';

/// @title 计算单个 tick 区间内的交换结果
/// @notice 在当前流动性保持不变的价格区间内，计算一步交换后的价格、输入、输出和手续费
library SwapMath {
    /// @notice 根据本步交换参数计算区间内的执行结果
    /// @dev amountRemaining 为正表示精确输入，为负表示精确输出。精确输入时，amountIn 与 feeAmount 之和
    /// 不会超过剩余输入。本函数只处理当前 tick 区间；到达目标价格后由池继续跨 tick 并更新流动性。
    /// @param sqrtRatioCurrentX96 池当前平方根价格
    /// @param sqrtRatioTargetX96 本步不可越过的目标价格，价格方向同时决定交换方向
    /// @param liquidity 当前 tick 区间内可用流动性
    /// @param amountRemaining 尚待交换的输入量或输出量
    /// @param feePips 从输入资产收取的费率，单位为百万分之一
    /// @return sqrtRatioNextX96 本步结束后的平方根价格，不超过目标价格
    /// @return amountIn 本步实际使用的 token0 或 token1 输入量
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
        // 当前价格高于目标价格表示 token0 换 token1，价格向下移动；否则价格向上移动
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
            // 精确输入：先扣除最大可能手续费，再判断净输入是否足以到达目标价格
            // amountRemaining = 1e18
            // liquidity = 973798273304651675783298
            // tickLower  sqrtRatioTargetX96 = 3952629513152786976618542036214
            // currentTick sqrtRatioCurrentX96 = 4687139750112641453566970974490
            // amountRemainingLessFee = amountRemaining * 997000 / 1e6;
            uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
            // zeroForOne=true  amountIn = 3058809464533194827856 =  liquidity * 2**96 * (sqrt_p - sqrt_pl) / sqrt_p / sqrt_pl
            // zeroForOne=false amountIn = 5979871796716035528730 = liquidity * (sqrt_p - sqrt_pnext) / 2**96
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);

            // 净输入足够时直接到达 tick 边界；否则全部净输入在当前区间成交并计算中间价格
            if (amountRemainingLessFee >= amountIn) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                // sqrtRatioNextX96 = 4686857862302283304824242238675 = liquidity * 2**96 * sqrtPX96 / (liquidity * 2**96 + amount * sqrtPX96)
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
        } else {
            // 精确输出：先计算到达目标价格最多能输出多少，再判断是否需要停在区间中间
            // amountRemaining = -1e18
            // liquidity = 973798273304651675783298
            // currentTick  sqrtRatioCurrentX96 = 4686857862302283304824242238675
            // tickUpper sqrtRatioTargetX96 = 5335411734972968923768194060979
            // amountRemainingLessFee = amountRemaining * 997000 / 1e6;
            // amountOut = 2000989999999999999999 = liquidity * 2**96 * (sqrt_pu - sqrt_p) / sqrt_pu / sqrt_p
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);
            if (uint256(-amountRemaining) >= amountOut) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                // sqrtRatioNextX96 = 4687142597637243141201475390809 = liquidity * 2**96 * sqrt_p / (liquidity * 2**96 - amount * sqrt_p)
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
        }

        // 是否已经完整走到本步目标价格
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

        // 根据实际起止价格重新计算本步输入和输出；此前计算结果仅在恰好到达目标时可复用
        if (zeroForOne) {
            // amountIn = 990000000000000000 =  liquidity * 2**96 * (sqrt_p - sqrt_pl) / sqrt_p / sqrt_pl
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            // amountOut = 3464700610000549890239 = liquidity * (sqrt_p - sqrt_pnext) / 2**96
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false);
        } else {
            // amountIn = 3499699711990536033126 = liquidity * (sqrt_pnext - sqrt_p) / 2**96
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
            // amountOut = 1000000000000000000 = liquidity * 2**96 * (sqrt_pnext - sqrt_p) / sqrt_pext / sqrt_p
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        }

        // 精确输出模式下，舍入误差不能让实际输出超过用户剩余需要的数量
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // 计算兑换手续费
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // 未到达目标价格说明用户的最大输入已全部用完，扣除实际交换输入后的余额即手续费
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
