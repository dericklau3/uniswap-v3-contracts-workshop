// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/libraries/Path.sol';
import '../v3-periphery/libraries/PoolAddress.sol';
import '../v3-periphery/libraries/CallbackValidation.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './interfaces/IV3SwapRouter.sol';
import './base/PeripheryPaymentsWithFeeExtended.sol';
import './base/OracleSlippage.sol';
import './libraries/Constants.sol';

/// @title Uniswap V3 兑换路由
/// @notice 无状态 V3 兑换路由，支持单跳/多跳、精确输入/精确输出，并配合扩展支付逻辑。
abstract contract V3SwapRouter is IV3SwapRouter, PeripheryPaymentsWithFeeExtended, OracleSlippage {
    using Path for bytes;
    using SafeCast for uint256;

    /// @dev exact output 输入缓存的占位值；真实 amountIn 不会等于 uint256 最大值。
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev exact output 反向多跳用到的临时输入金额缓存，调用结束后必须恢复默认值。
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    /// @dev 根据代币对和手续费计算 V3 池子地址；该地址可能尚未部署。
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

    /// @notice V3 池子 swap 回调，路由在这里支付当前池子要求的输入代币。
    /// @dev 精确输入直接付款；精确输出按反向 path 继续触发前一跳，直到最后向用户收取真实输入。
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
            // exact output 采用反向执行：还有前置池子就继续 swap，否则向最终 payer 付款。
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                amountInCached = amountToPay;
                // exact output 的 path 反向编码，此时 tokenOut 实际上是用户要支付的输入代币。
                pay(tokenOut, data.payer, msg.sender, amountToPay);
            }
        }
    }

    /// @dev 执行单跳精确输入 swap，返回本跳输出数量。
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // 把 recipient 占位常量替换为实际地址，便于 multicall 中复用参数。
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

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

    /// @notice 单池精确输入兑换，输入可指定为合约当前余额。
    function exactInputSingle(ExactInputSingleParams memory params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // amountIn 为 CONTRACT_BALANCE 时，表示把路由合约里该输入代币的余额全部换掉。
        bool hasAlreadyPaid;
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            params.amountIn = IERC20(params.tokenIn).balanceOf(address(this));
        }

        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut),
                payer: hasAlreadyPaid ? address(this) : msg.sender
            })
        );
        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @notice 多池精确输入兑换，每一跳输出会成为下一跳输入。
    function exactInput(ExactInputParams memory params) external payable override returns (uint256 amountOut) {
        // amountIn 为 CONTRACT_BALANCE 时，用 path 第一个 token 在本合约里的全部余额作为输入。
        bool hasAlreadyPaid;
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            (address tokenIn, , ) = params.path.decodeFirstPool();
            params.amountIn = IERC20(tokenIn).balanceOf(address(this));
        }

        address payer = hasAlreadyPaid ? address(this) : msg.sender;

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // 前一跳输出成为后一跳输入；中间资产由路由合约临时托管。
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // 中间跳输出留在本合约。
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(), // 当前 swap 只需要 path 中第一个池子。
                    payer: payer
                })
            );

            // 还有下一跳就推进 path；最后一跳输出即为最终 amountOut。
            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @dev 执行单跳精确输出 swap，返回本跳需要的输入数量。
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // 把 recipient 占位常量替换为实际地址，便于 multicall 中复用参数。
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

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
        // 未指定价格限制时，要求本跳必须完整收到目标输出，避免部分成交语义泄漏到上层。
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @notice 单池精确输出兑换，限制最大输入金额。
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        // 单跳可直接使用 swap 返回值，避免读取 amountInCached。
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );

        require(amountIn <= params.amountInMaximum, 'Too much requested');
        // 单跳虽然不依赖缓存，也恢复默认值，避免后续调用读到旧状态。
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @notice 多池精确输出兑换，从最终输出反向执行，计算用户实际需要支付的输入。
    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
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
