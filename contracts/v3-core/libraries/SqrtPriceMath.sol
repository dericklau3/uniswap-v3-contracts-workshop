// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './FullMath.sol';
import './UnsafeMath.sol';
import './FixedPoint96.sol';

/// @title 基于 Q64.96 平方根价格和流动性的数学函数
/// @notice 使用 Q64.96 格式的平方根价格与流动性计算价格变化和 token 数量变化
/// @dev 它连接了三类业务量：当前平方根价格、某个区间内固定的 liquidity、交易的 token 数量。
/// 在一个 tick 区间内 liquidity 不变，因此输入 token 数量可以唯一决定新价格，反过来也可由起止价格
/// 算出所需 token0/token1。Pool 的 swap、mint 和 burn 最终都依赖这些换算。
///
/// 取整方向属于资金安全规则，不只是数学细节：池计算用户“应付”时通常向上取整，避免少收；
/// 计算用户“应得输出”时通常向下取整，避免多付。最多 1 wei 的偏差始终保守地留在池内。
library SqrtPriceMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /// @notice 根据 token0 数量变化计算下一平方根价格
    /// @dev 始终向上取整。精确输出时必须让价格至少移动到足以提供目标输出的位置；
    /// 精确输入时则要避免因向下取整导致输出过多。精确公式为
    /// liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96)，乘法溢出时改用等价公式
    /// liquidity / (liquidity / sqrtPX96 +- amount)。
    /// @param sqrtPX96 token0 变化前的起始平方根价格
    /// @param liquidity 当前可用流动性
    /// @param amount 加入或移出虚拟储备的 token0 数量
    /// @param add 是否向虚拟储备加入 token0
    /// @return 加入或移除 token0 后的平方根价格
    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // amount 为 0 时直接返回，避免后续舍入使结果偏离原价格
        if (amount == 0) return sqrtPX96;
        // liquidity * 2**96
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            uint256 product;
            if ((product = amount * sqrtPX96) / amount == sqrtPX96) {
                // liquidity * 2**96  + (amount * sqrtPX96)
                uint256 denominator = numerator1 + product;
                if (denominator >= numerator1)
                    // 结果始终可放入 160 位
                    // liquidity * 2**96 * sqrtPX96 / (liquidity * 2**96 + amount * sqrtPX96)
                    return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
            }

            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96).add(amount)));
        } else {
            uint256 product;
            // product 溢出意味着分母计算也不安全，同时必须显式防止分母下溢
            // liquidity * 2**96 * sqrt_p / (liquidity * 2**96 - amount * sqrt_p)
            require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
            uint256 denominator = numerator1 - product;
            return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
        }
    }

    /// @notice 根据 token1 数量变化计算下一平方根价格
    /// @dev 始终向下取整。精确输出时必须让价格至少移动到足以提供目标输出的位置；
    /// 精确输入时则要避免因价格移动过多而输出过量。计算结果与无损公式
    /// sqrtPX96 +- amount / liquidity 的误差小于 1 wei。
    /// @param sqrtPX96 token1 变化前的起始平方根价格
    /// @param liquidity 当前可用流动性
    /// @param amount 加入或移出虚拟储备的 token1 数量
    /// @param add 是否向虚拟储备加入 token1
    /// @return 加入或移除 token1 后的平方根价格
    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // 加入 token1 时商向下取整，移出时商向上取整；常见输入使用移位除法以节省 gas
        if (add) {
            uint256 quotient =
                (
                    amount <= type(uint160).max
                        ? (amount << FixedPoint96.RESOLUTION) / liquidity
                        : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
                );

            return uint256(sqrtPX96).add(quotient).toUint160();
        } else {
            uint256 quotient =
                (
                    amount <= type(uint160).max
                        ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
                        : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
                );

            require(sqrtPX96 > quotient);
            // 结果始终可放入 160 位
            return uint160(sqrtPX96 - quotient);
        }
    }

    /// @notice 根据精确输入的 token0 或 token1 数量计算下一平方根价格
    /// @dev 价格或流动性为 0、或下一价格越界时回退
    /// @param sqrtPX96 输入发生前的起始平方根价格
    /// @param liquidity 当前可用流动性
    /// @param amountIn 本次交换输入的 token0 或 token1 数量
    /// @param zeroForOne 是否以 token0 换 token1
    /// @return sqrtQX96 加入输入资产后的平方根价格
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 选择保守舍入方向，确保本步价格不会越过目标价格
        return
            zeroForOne
                ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
                : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @notice 根据精确输出的 token0 或 token1 数量计算下一平方根价格
    /// @dev 价格或流动性为 0、或下一价格越界时回退
    /// @param sqrtPX96 输出发生前的起始平方根价格
    /// @param liquidity 当前可用流动性
    /// @param amountOut 本次交换输出的 token0 或 token1 数量
    /// @param zeroForOne 是否以 token0 换 token1
    /// @return sqrtQX96 移出输出资产后的平方根价格
    function getNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 选择保守舍入方向，确保价格移动足以覆盖指定输出量
        // liquidity * 2**96 * sqrt_p / (liquidity * 2**96 - amount * sqrt_p)
        return
            zeroForOne
                ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
                : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }

    /// @notice 计算两个价格之间对应的 token0 数量变化
    /// @dev 计算 liquidity / sqrt(lower) - liquidity / sqrt(upper)，即
    /// liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))。
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 当前可用流动性
    /// @param roundUp token 数量是否向上取整
    /// @return amount0 在两个价格之间维持指定流动性所需的 token0 数量
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        // liquidity * 2**96
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);
        // first swap
        // liquidity * 2**96 * (sqrt_p - sqrt_pl) / sqrt_p / sqrt_pl
        return
            roundUp
                ? UnsafeMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice 计算两个价格之间对应的 token1 数量变化
    /// @dev 计算 liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 当前可用流动性
    /// @param roundUp token 数量是否向上取整
    /// @return amount1 在两个价格之间维持指定流动性所需的 token1 数量
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        // liquidity * (sqrt_p - sqrt_pnext) / 2**96
        return
            roundUp
                ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice 计算带符号流动性变化对应的 token0 数量变化
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 待换算的流动性变化，负数表示移除流动性
    /// @return amount0 两个价格之间与该流动性变化对应的 token0 数量
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount0) {
        return
            liquidity < 0
                ? -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }

    /// @notice 计算带符号流动性变化对应的 token1 数量变化
    /// @param sqrtRatioAX96 一个平方根价格
    /// @param sqrtRatioBX96 另一个平方根价格
    /// @param liquidity 待换算的流动性变化，负数表示移除流动性
    /// @return amount1 两个价格之间与该流动性变化对应的 token1 数量
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount1) {
        return
            liquidity < 0
                ? -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }
}
