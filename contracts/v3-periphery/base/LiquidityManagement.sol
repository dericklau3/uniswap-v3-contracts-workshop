// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';

import '../libraries/PoolAddress.sol';
import '../libraries/CallbackValidation.sol';
import '../libraries/LiquidityAmounts.sol';

import './PeripheryPayments.sol';
import './PeripheryImmutableState.sol';


/// @title 流动性管理函数
/// @notice 给外围合约提供“计算流动性 -> 调用池 mint -> 回调付款 -> 检查滑点”的完整加仓流程。
/// @dev 用户通常不会直接调用 core pool，因为 core 接口要求调用者实现 mint callback。
/// PositionManager 继承本合约后，可以替用户完成以下编排：
/// 1. 根据 token 对和费率确定唯一池地址；
/// 2. 读取当前价格，把用户愿意投入的两种 token 换算为可铸造 liquidity；
/// 3. 调用 pool.mint，让池先更新仓位并计算实际应收金额；
/// 4. pool 回调本合约，本合约从 payer 向真实池地址付款；
/// 5. mint 返回后检查实际用量没有跌破用户设置的最小值。
///
/// `amountDesired` 表示最多愿意投入多少，未必会全部使用；集中流动性仓位的 token 配比由当前价格决定。
/// `amountMin` 则是交易在链上执行时的价格保护，防止价格变化导致实际投入比例偏离用户预期。
abstract contract LiquidityManagement is IUniswapV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    struct MintCallbackData {
        // 唯一确定回调来源池的 token0、token1 和 fee。
        PoolAddress.PoolKey poolKey;
        // 真正承担 token 支出的地址；通常是外部用户，也可能是本合约。
        address payer;
    }

    /// @notice V3 池子 mint 后回调外围合约，外围合约在这里替 LP 支付应付的 token0/token1。
    /// @dev 回调参数不是“用户想投入的数量”，而是 core pool 按执行时价格算出的实际欠款。
    /// 必须先用 factory 与 poolKey 重新推导合法池地址并校验 `msg.sender`，否则攻击者可以伪造回调，
    /// 填入任意 token 和金额，诱导外围合约从 payer 账户向攻击者转账。
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        // decoded.payer 是实际出资人，msg.sender 是正在 mint 的 UniswapV3Pool。
        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice 给已初始化池子添加流动性。
    /// @dev 先用当前池子价格把用户期望投入的 token0/token1 换算成最大可铸造流动性，
    /// 再调用 pool.mint，由 mint 回调完成实际付款，并用 amount0Min/amount1Min 做滑点保护。
    ///
    /// 换算结果取受限更强的一侧：如果当前价格下 100 token0 只能匹配 20 token1，
    /// 而用户提供了 100 token0 和 50 token1，那么 liquidity 由 20 token1 对应的组合决定，
    /// 多余 token1 不会被池拿走。最终 `amount0/amount1` 是实际使用量，调用方可据此展示或退款。
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IUniswapV3Pool pool
        )
    {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});

        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // 根据当前价格、仓位区间和用户期望投入数量计算可铸造流动性。
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');
    }
}
