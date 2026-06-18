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

    /// @notice Uniswap V3 Pool 在 swap 过程中会回调这个函数
    /// @dev
    /// Quoter 合约并不是真的想完成 swap，而是“模拟一次 swap”，拿到报价结果。
    ///
    /// 正常 SwapRouter 的流程是：
    /// 1. 调用 pool.swap(...)
    /// 2. Pool 内部根据价格、tick、流动性计算 token 输入/输出数量
    /// 3. Pool 先把 output token 转给 recipient
    /// 4. Pool 回调 msg.sender.uniswapV3SwapCallback(...)
    /// 5. 调用者在 callback 里把 input token 付给 Pool
    /// 6. Pool 检查自己是否真的收到了 input token
    ///
    /// 但是 Quoter 的逻辑不同：
    /// 1. Quoter 调用 pool.swap(...)，让 Pool 按真实 swap 逻辑计算一遍
    /// 2. Pool 算完后进入 uniswapV3SwapCallback
    /// 3. Quoter 在 callback 里不付款
    /// 4. Quoter 直接 revert，并把报价结果塞进 revert data
    /// 5. 外层 try/catch 捕获这个 revert
    /// 6. 从 revert data 里解析出 amountOut 或 amountIn
    ///
    /// 所以这里的 revert 不是错误，而是 Quoter 用来“返回报价数据”的技巧。
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view override {
        /// amount0Delta 和 amount1Delta 是 Pool 告诉调用者：
        /// 这次 swap 之后，调用者需要给 Pool 补多少 token0 / token1。
        ///
        /// 规则：
        /// - 如果 amount0Delta > 0，说明调用者需要支付 token0 给 Pool
        /// - 如果 amount1Delta > 0，说明调用者需要支付 token1 给 Pool
        /// - 如果 amount0Delta < 0，说明 Pool 给了调用者 token0
        /// - 如果 amount1Delta < 0，说明 Pool 给了调用者 token1
        ///
        /// 正常 swap 中，一定至少有一个 delta 是正数。
        /// 如果两个都不是正数，说明没有任何 token 需要支付，
        /// 通常代表这个 swap 完全发生在零流动性区域内，这是不支持的。
        require(amount0Delta > 0 || amount1Delta > 0); // 不支持完全发生在零流动性区域内的 swap。
        /// 从 path 中解析出当前这一步池子的 tokenIn、tokenOut、fee。
        ///
        /// path 是 Quoter/Router 传进来的交易路径。
        /// 对于单池兑换，path 类似：
        /// tokenIn -> fee -> tokenOut
        ///
        /// 对于多跳兑换，path 可能类似：
        /// tokenA -> fee1 -> tokenB -> fee2 -> tokenC
        ///
        /// decodeFirstPool() 只解析当前第一段池子：
        /// tokenIn、tokenOut、fee。
        (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();
        /// 验证 msg.sender 必须是 Uniswap V3 Factory 创建出来的合法 Pool。
        ///
        /// 因为任何合约都可以主动调用 uniswapV3SwapCallback，
        /// 如果不验证 msg.sender，恶意合约可以伪造 callback 调用。
        ///
        /// verifyCallback 会根据 factory、tokenIn、tokenOut、fee
        /// 计算出真实 Pool 地址，并要求 msg.sender 等于这个 Pool 地址。
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        /// 根据 amount0Delta / amount1Delta 判断：  根据 amount0Delta / amount1Delta 判断：
        /// 1. 本次 swap 是 exactInput 还是 exactOutput
        /// 2. 需要支付给 Pool 的 token 数量 amountToPay
        /// 3. 从 Pool 收到的 token 数量 amountReceived
        ///
        /// 背景：
        /// Uniswap V3 Pool 内部的 token0 / token1 地址是按大小排序的：
        /// token0 < token1
        ///
        /// 但是 path 里的 tokenIn / tokenOut 是用户指定的兑换方向：
        /// 用户可能是 token0 -> token1
        /// 也可能是 token1 -> token0
        ///
        /// 所以这里要结合：
        /// - amount0Delta / amount1Delta 谁是正数
        /// - tokenIn 和 tokenOut 的地址大小关系
        ///
        /// 来判断当前这次 callback 对应的是 exactInput 还是 exactOutput。
        ///
        /// 情况一：amount0Delta > 0
        /// 说明 Pool 要求调用者支付 token0。
        /// 那么：
        /// - amountToPay = amount0Delta，也就是要支付的 token0 数量
        /// - amountReceived = -amount1Delta，也就是收到的 token1 数量
        ///
        /// 如果 tokenIn < tokenOut，说明：
        /// - tokenIn 是 token0
        /// - tokenOut 是 token1
        /// - 用户输入 token0，收到 token1
        /// - 这是 exactInput 方向
        ///
        /// 如果 tokenIn > tokenOut，说明：
        /// - tokenIn 是 token1
        /// - tokenOut 是 token0
        /// - 但当前 Pool 要求支付 token0
        /// - 这说明当前是在 exactOutput 的反向计算中
        ///
        /// 情况二：amount1Delta > 0
        /// 说明 Pool 要求调用者支付 token1。
        /// 那么：
        /// - amountToPay = amount1Delta，也就是要支付的 token1 数量
        /// - amountReceived = -amount0Delta，也就是收到的 token0 数量
        ///
        /// 如果 tokenOut < tokenIn，说明：
        /// - tokenOut 是 token0
        /// - tokenIn 是 token1
        /// - 用户输入 token1，收到 token0
        /// - 这是 exactInput 方向
        ///
        /// 否则就是 exactOutput 方向。
        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));
        if (isExactInput) {
            /// exactInput 的意思是：
            /// 用户已经确定输入多少 tokenIn，想知道最多能收到多少 tokenOut。
            ///
            /// 例如：
            /// 输入 1 ETH，能收到多少 USDC？
            ///
            /// 在这种情况下，Pool 已经通过 swap 计算出了输出数量。
            /// 这里的 amountReceived 就是本次模拟 swap 能收到的 tokenOut 数量。
            ///
            /// Quoter 不会真的支付 tokenIn 给 Pool。
            /// 它直接用 revert 把 amountReceived 返回给外层 catch。
            ///
            /// 为什么不用 return？
            /// 因为这个函数是 Pool 回调的 callback，
            /// callback 的正常职责是付款，不是返回报价。
            /// 所以 Quoter 使用 revert data 来携带报价结果。
            ///
            /// revert 后，整个 pool.swap 的状态修改都会回滚，
            /// 所以不会真的成交，也不会真的转账。
            assembly {
                /// 获取当前空闲内存指针。
                let ptr := mload(0x40)
                /// 把 amountReceived 写入内存。
                /// 这里写入 32 字节，因为 uint256 正好占 32 字节。
                mstore(ptr, amountReceived)
                /// 主动 revert，并把 ptr 开始的 32 字节作为 revert data 返回。
                ///
                /// 外层 quoteExactInputSingle / quoteExactInput 会 catch 到这个 reason，
                /// 然后 abi.decode(reason, (uint256)) 得到 amountReceived。
                revert(ptr, 32)
            }
        } else {
            /// exactOutput 的意思是：
            /// 用户已经确定想收到多少 tokenOut，想知道最少需要输入多少 tokenIn。
            ///
            /// 例如：
            /// 想收到 1000 USDC，需要支付多少 ETH？
            ///
            /// 在 exactOutput 模式下，Quoter 会传入一个期望输出数量。
            /// Pool 通过反向 swap 计算出需要支付的输入数量。
            ///
            /// amountReceived 表示本次模拟中实际收到的输出 token 数量。
            /// amountOutCached 是 Quoter 提前缓存的目标输出数量。
            ///
            /// 如果 amountOutCached != 0，说明当前是 exactOutput 报价流程，
            /// 必须确认 Pool 模拟出来的实际输出数量等于用户想要的输出数量。
            ///
            /// 如果不相等，说明模拟没有完整满足目标输出，应该 revert。
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            /// 对于 exactOutput，用户关心的不是收到多少，
            /// 因为收到多少已经提前指定了。
            ///
            /// 用户关心的是：
            /// 为了收到指定数量的 tokenOut，需要支付多少 tokenIn。
            ///
            /// 所以这里通过 revert 返回 amountToPay。
            assembly {
                /// 获取当前空闲内存指针
                let ptr := mload(0x40)
                /// 把 amountToPay 写入内存。
                /// amountToPay 就是为了拿到目标输出，需要支付的输入 token 数量。
                mstore(ptr, amountToPay)
                /// 主动 revert，并把 amountToPay 放到 revert data 中。
                ///
                /// 外层 quoteExactOutputSingle / quoteExactOutput 会 catch 到这个 reason，
                /// 然后 abi.decode(reason, (uint256)) 得到 amountToPay。
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
