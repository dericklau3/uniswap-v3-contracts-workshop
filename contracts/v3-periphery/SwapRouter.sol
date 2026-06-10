// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './interfaces/ISwapRouter.sol';
import './base/PeripheryImmutableState.sol';
import './base/PeripheryValidation.sol';
import './base/PeripheryPaymentsWithFee.sol';
import './base/Multicall.sol';
import './base/SelfPermit.sol';
import './libraries/Path.sol';
import './libraries/PoolAddress.sol';
import './libraries/CallbackValidation.sol';
import './interfaces/external/IWETH9.sol';

/// @title Uniswap V3 兑换路由
/// @notice 无状态 V3 兑换路由，负责串联一个或多个池子的 swap，并在回调中完成付款。
/// @dev 精确输入按路径正向执行：第一跳从用户付款，中间输出暂存在 Router，后续跳用中间资产付款。
/// 精确输出则从最后一池反向计算：为了拿到固定最终输出，callback 递归触发前一池，
/// 直到算出并收取用户的真实输入，因此 exact-output path 的编码方向与 exact-input 相反。
///
/// Pool 先转出输出再回调收输入。Router 必须验证回调者是 Factory 对应的真实池，
/// 否则攻击合约可伪造欠款请求。最小输出、最大输入和价格限制共同承担滑点保护。
contract SwapRouter is
    ISwapRouter,
    PeripheryImmutableState,
    PeripheryValidation,
    PeripheryPaymentsWithFee,
    Multicall,
    SelfPermit
{
    using Path for bytes;
    using SafeCast for uint256;

    /// @dev exact output 临时缓存的占位值；真实计算出的 amountIn 不可能等于 uint256 最大值。
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev exact output 多跳会反向执行，最终输入金额通过这个临时变量带回外层函数。
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    constructor(address _factory, address _WETH9) PeripheryImmutableState(_factory, _WETH9) {}

    /// @dev 根据代币对和费率计算池子地址；该地址可能还没有实际部署。
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    /// @notice V3 池子 swap 后回调路由，路由在这里支付本跳需要的输入代币。
    /// @dev 精确输入路径按正向逐跳付款；精确输出路径按反向递归发起上一跳，最后才由用户付款。
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // 不支持完全发生在零流动性区域内的 swap。
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            // exact output 是反向路径：还有前置池子就继续发起下一次 swap，否则向最终付款人收钱。
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                amountInCached = amountToPay;
                tokenIn = tokenOut; // exact output 的 path 是反向编码，这里把输入/输出角色换回来。
                pay(tokenIn, data.payer, msg.sender, amountToPay);
            }
        }
    }

    /// @dev 执行单跳精确输入 swap，返回本跳实际收到的输出数量。
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // recipient 为 0 时表示把中间输出先留在路由合约，方便后续多跳继续使用。
        if (recipient == address(0)) recipient = address(this);

        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) =
            getPool(tokenIn, tokenOut, fee).swap(
                recipient,
                zeroForOne,
                amountIn.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @notice 单池精确输入兑换：用户指定输入数量，要求输出不少于 amountOutMinimum。
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
        );
        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @notice 多池精确输入兑换：每一跳输出都会作为下一跳输入。
    function exactInput(ExactInputParams memory params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address payer = msg.sender; // 第一跳由用户付款。

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // 前一跳输出会成为后一跳输入；中间跳输出先由路由合约托管。
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // 中间跳由路由暂存资产。
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(), // 当前 swap 只需要 path 中第一个池子。
                    payer: payer
                })
            );

            // 如果还有池子，跳过 path 中已完成的 token；最后一跳结束后得到最终 amountOut。
            if (hasMultiplePools) {
                payer = address(this); // 用户已在第一跳付款，后续跳由路由用中间资产付款。
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @dev 执行单跳精确输出 swap，返回本跳需要支付的输入数量。
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // recipient 为 0 时表示把本跳输出留在路由合约，用于反向多跳的中间支付。
        if (recipient == address(0)) recipient = address(this);

        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) =
            getPool(tokenIn, tokenOut, fee).swap(
                recipient,
                zeroForOne,
                -amountOut.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // 如果用户没有指定价格限制，要求本跳必须完整拿到目标输出数量。
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @notice 单池精确输出兑换：用户指定要拿到的输出数量，并限制最大输入。
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // 单跳可直接用 swap 返回值，避免读取 amountInCached。
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );

        require(amountIn <= params.amountInMaximum, 'Too much requested');
        // 即使单跳没有使用缓存，也恢复默认值，保持状态变量语义干净。
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @notice 多池精确输出兑换：从最终输出反向发起 swap，逐跳推导需要的输入。
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // payer 固定为用户是安全的：反向执行时用户只为第一笔实际发生的“最终输出”swap 付款，
        // 更前面的跳会在嵌套回调中由路由持有的中间资产继续支付。
        exactOutputInternal(
            params.amountOut,
            params.recipient,
            0,
            SwapCallbackData({path: params.path, payer: msg.sender})
        );

        amountIn = amountInCached;
        require(amountIn <= params.amountInMaximum, 'Too much requested');
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }
}
