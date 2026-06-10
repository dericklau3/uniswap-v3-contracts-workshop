// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/libraries/TickBitmap.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '@uniswap/v3-periphery/contracts/libraries/Path.sol';
import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import '@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import '../base/ImmutableState.sol';
import '../interfaces/IMixedRouteQuoterV1.sol';
import '../libraries/PoolTicksCounter.sol';
import '../libraries/UniswapV2Library.sol';

/// @title V2/V3 混合路径精确输入报价工具
/// @notice 在不真正完成 swap 的情况下，模拟 V2、V3 或混合路径的精确输入输出数量。
/// @notice 不支持精确输出报价，因为 exactOut 多跳需要依赖合约中间余额。
/// @dev V3 报价依赖回调 revert 携带数据，gas 不低，不应在链上业务路径中调用。
contract MixedRouteQuoterV1 is IMixedRouteQuoterV1, IUniswapV3SwapCallback, PeripheryImmutableState {
    using Path for bytes;
    using SafeCast for uint256;
    using PoolTicksCounter for IUniswapV3Pool;
    address public immutable factoryV2;
    /// @dev 通过 fee 的最高位标记该跳是 V2 还是 V3。
    // V3 最大 fee:          000011110100001001000000 (24 bits)
    // mask:       1 << 23 = 100000000000000000000000 = 十进制 8388608
    uint24 private constant flagBitmask = 8388608;

    /// @dev 保留字段，混合报价当前只支持 exact input。
    uint256 private amountOutCached;

    constructor(
        address _factory,
        address _factoryV2,
        address _WETH9
    ) PeripheryImmutableState(_factory, _WETH9) {
        factoryV2 = _factoryV2;
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    /// @dev 读取 V2 pair 储备量，并根据恒定乘积公式计算 amountIn 对应的 amountOut。
    function getPairAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) private view returns (uint256) {
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(factoryV2, tokenIn, tokenOut);
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @notice V3 swap 模拟回调，把报价结果、swap 后价格和 tick 编码进 revert data 返回。
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view override {
        require(amount0Delta > 0 || amount1Delta > 0); // 不支持完全发生在零流动性区域内的 swap。
        (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(-amount0Delta));

        IUniswapV3Pool pool = getPool(tokenIn, tokenOut, fee);
        (uint160 v3SqrtPriceX96After, int24 tickAfter, , , , , ) = pool.slot0();

        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                mstore(add(ptr, 0x20), v3SqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 0x60)
            }
        } else {
            /// 当前合约不支持 exact output 报价，走到这里直接回滚。
            revert('Exact output quote not supported');
        }
    }

    /// @dev 解析 V3 回调 revert data；正常报价返回 amount、swap 后 sqrtPrice 和 tick。
    function parseRevertReason(bytes memory reason)
        private
        pure
        returns (
            uint256 amount,
            uint160 sqrtPriceX96After,
            int24 tickAfter
        )
    {
        if (reason.length != 0x60) {
            if (reason.length < 0x44) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function handleV3Revert(
        bytes memory reason,
        IUniswapV3Pool pool,
        uint256 gasEstimate
    )
        private
        view
        returns (
            uint256 amount,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256
        )
    {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = pool.slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    /// @dev 查询单个 V3 池子的 exactIn 报价，并返回价格/tick/gas 信息。
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params memory params)
        public
        override
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        uint256 gasBefore = gasleft();
        try
            pool.swap(
                address(this), // 某些 token 不兼容 address(0) 作为收款地址。
                zeroForOne,
                params.amountIn.toInt256(),
                params.sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : params.sqrtPriceLimitX96,
                abi.encodePacked(params.tokenIn, params.fee, params.tokenOut)
            )
        {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            return handleV3Revert(reason, pool, gasEstimate);
        }
    }

    /// @dev 查询单个 V2 pair 的 exactIn 报价。
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        public
        view
        override
        returns (uint256 amountOut)
    {
        amountOut = getPairAmountOut(params.amountIn, params.tokenIn, params.tokenOut);
    }

    /// @dev 查询由 V2/V3 混合组成的 exactIn 路径报价。
    /// @notice 在 path 中用 0x800000 作为两个 token 之间的 fee，即表示该跳使用 V2 pair。
    function quoteExactInput(bytes memory path, uint256 amountIn)
        public
        override
        returns (
            uint256 amountOut,
            uint160[] memory v3SqrtPriceX96AfterList,
            uint32[] memory v3InitializedTicksCrossedList,
            uint256 v3SwapGasEstimate
        )
    {
        v3SqrtPriceX96AfterList = new uint160[](path.numPools());
        v3InitializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            if (fee & flagBitmask != 0) {
                amountIn = quoteExactInputSingleV2(
                    QuoteExactInputSingleV2Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn})
                );
            } else {
                /// 前一跳输出成为后一跳输入。
                (
                    uint256 _amountOut,
                    uint160 _sqrtPriceX96After,
                    uint32 _initializedTicksCrossed,
                    uint256 _gasEstimate
                ) =
                    quoteExactInputSingleV3(
                        QuoteExactInputSingleV3Params({
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            fee: fee,
                            amountIn: amountIn,
                            sqrtPriceLimitX96: 0
                        })
                    );
                v3SqrtPriceX96AfterList[i] = _sqrtPriceX96After;
                v3InitializedTicksCrossedList[i] = _initializedTicksCrossed;
                v3SwapGasEstimate += _gasEstimate;
                amountIn = _amountOut;
            }
            i++;

            /// 还有下一跳就推进 path，否则返回最终输出和 V3 跳统计。
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountIn, v3SqrtPriceX96AfterList, v3InitializedTicksCrossedList, v3SwapGasEstimate);
            }
        }
    }
}
