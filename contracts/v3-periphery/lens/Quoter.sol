// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import '../interfaces/IQuoter.sol';
import '../base/PeripheryImmutableState.sol';
import '../libraries/Path.sol';
import '../libraries/PoolAddress.sol';
import '../libraries/CallbackValidation.sol';

/// @title Swap 报价工具
/// @notice 在不真正完成 swap 的情况下，模拟得到预期输出或所需输入。
/// @dev 这些函数依赖“回调中 revert 并携带报价数据”的技巧，gas 不低，不应在链上业务路径中调用。
/// V3 没有简单的只读报价公式，因为真实成交可能跨越多个 tick 并多次改变活跃流动性。
/// Quoter 调用真实 pool.swap，在 callback 中把结果编码进 revert data；外层捕获后解码，
/// Pool 的临时状态则随回退全部撤销。前端通常通过 `eth_call` 使用它。
contract Quoter is IQuoter, IUniswapV3SwapCallback, PeripheryImmutableState {
    using Path for bytes;
    using SafeCast for uint256;

    /// @dev exact output 报价时缓存目标输出数量，用于在回调里确认池子给足输出。
    uint256 private amountOutCached;

    constructor(address _factory, address _WETH9) PeripheryImmutableState(_factory, _WETH9) {}

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    /// @notice V3 swap 模拟回调，在这里把报价结果编码进 revert data 返回给外层。
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view override {
        require(amount0Delta > 0 || amount1Delta > 0); // 不支持完全发生在零流动性区域内的 swap。
        (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));
        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                revert(ptr, 32)
            }
        } else {
            // 如果缓存了目标输出，必须确认模拟 swap 完整收到该输出数量。
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountToPay)
                revert(ptr, 32)
            }
        }
    }

    /// @dev 解析回调 revert data；正常报价返回 32 字节数字，真实错误则透传 revert reason。
    function parseRevertReason(bytes memory reason) private pure returns (uint256) {
        if (reason.length != 32) {
            if (reason.length < 68) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256));
    }

    /// @notice 查询单池精确输入兑换的输出数量。
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) public override returns (uint256 amountOut) {
        bool zeroForOne = tokenIn < tokenOut;

        try
            getPool(tokenIn, tokenOut, fee).swap(
                address(this), // 某些 token 不兼容 address(0) 作为收款地址。
                zeroForOne,
                amountIn.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encodePacked(tokenIn, fee, tokenOut)
            )
        {} catch (bytes memory reason) {
            return parseRevertReason(reason);
        }
    }

    /// @notice 查询多池精确输入兑换的最终输出数量。
    function quoteExactInput(bytes memory path, uint256 amountIn) external override returns (uint256 amountOut) {
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            // 前一跳输出成为后一跳输入。
            amountIn = quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0);

            // 还有下一跳就推进 path，否则当前 amountIn 就是最终输出。
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                return amountIn;
            }
        }
    }

    /// @notice 查询单池精确输出兑换所需的输入数量。
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) public override returns (uint256 amountIn) {
        bool zeroForOne = tokenIn < tokenOut;

        // 未指定价格限制时，缓存目标输出，回调里会校验必须完整收到。
        if (sqrtPriceLimitX96 == 0) amountOutCached = amountOut;
        try
            getPool(tokenIn, tokenOut, fee).swap(
                address(this), // 某些 token 不兼容 address(0) 作为收款地址。
                zeroForOne,
                -amountOut.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encodePacked(tokenOut, fee, tokenIn)
            )
        {} catch (bytes memory reason) {
            if (sqrtPriceLimitX96 == 0) delete amountOutCached; // 清理缓存。
            return parseRevertReason(reason);
        }
    }

    /// @notice 查询多池精确输出兑换所需的最终输入数量。
    function quoteExactOutput(bytes memory path, uint256 amountOut) external override returns (uint256 amountIn) {
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            (address tokenOut, address tokenIn, uint24 fee) = path.decodeFirstPool();

            // 精确输出按反向路径报价：后一跳所需输入会成为前一跳目标输出。
            amountOut = quoteExactOutputSingle(tokenIn, tokenOut, fee, amountOut, 0);

            // 还有上一跳就推进 path，否则当前 amountOut 就是最终所需输入。
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                return amountOut;
            }
        }
    }
}
