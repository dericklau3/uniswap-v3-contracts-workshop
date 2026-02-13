// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {
    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
    /// @param sqrtRatioTargetX96 The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
    /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
    /// @return sqrtRatioNextX96 The price after swapping the amount in/out, not to exceed the price target
    /// @return amountIn The amount to be swapped in, of either token0 or token1, based on the direction of the swap
    /// @return amountOut The amount to be received, of either token0 or token1, based on the direction of the swap
    /// @return feeAmount The amount of input that will be taken as a fee
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
        // first swap
        // sqrtRatioCurrentX96 >= sqrtRatioTargetX96 = sqrtPriceX96 >= sqrtPriceX96_lower
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
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

            // 区间内的流动性不足，无法将输入的全部兑换
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

        // 3952629513152786976618542036214 == 4686857862302283304824242238675
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

        // get the input/output amounts
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

        // cap the output amount to not exceed the remaining output amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // 计算兑换费用
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // we didn't reach the target, so take the remainder of the maximum input as fee
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
