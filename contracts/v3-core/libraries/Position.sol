// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title 流动性头寸
/// @notice 头寸表示某个所有者在上下 tick 边界之间提供的流动性
/// @dev 除流动性外，头寸还保存手续费增长快照和待领取手续费
library Position {
    // 每个用户头寸保存的信息
    struct Info {
        // 该头寸拥有的流动性
        uint128 liquidity;
        // 上次更新流动性或手续费时，区间内每单位流动性的手续费增长快照
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // 已结算但尚未领取的 token0 和 token1 手续费
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice 根据所有者和价格边界返回头寸状态
    /// @dev 同一所有者在相同上下 tick 之间只对应一个 core 头寸键
    /// @param self 保存全部用户头寸的映射
    /// @param owner 头寸所有者地址
    /// @param tickLower 头寸下边界 tick
    /// @param tickUpper 头寸上边界 tick
    /// @return position 指定头寸的状态引用
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    /// @notice 将自上次更新以来累计的手续费记入用户头寸，并更新流动性
    /// @dev 手续费按“区间内增长差值 × 更新前流动性”结算，确保本次新增流动性不会分享历史手续费
    /// @param self 待更新的单个头寸
    /// @param liquidityDelta 本次头寸操作引起的流动性变化
    /// @param feeGrowthInside0X128 头寸区间内 token0 的当前每单位流动性手续费增长
    /// @param feeGrowthInside1X128 头寸区间内 token1 的当前每单位流动性手续费增长
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        Info memory _self = self;

        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, 'NP'); // 不允许对零流动性头寸仅触发手续费结算
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(_self.liquidity, liquidityDelta);
        }

        // 按上次快照与当前累计值之差，计算旧流动性在此期间赚取的手续费
        uint128 tokensOwed0 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0X128 - _self.feeGrowthInside0LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );
        uint128 tokensOwed1 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1X128 - _self.feeGrowthInside1LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );

        // 更新流动性、手续费增长快照和待领取手续费
        if (liquidityDelta != 0) self.liquidity = liquidityNext;
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // 这里允许 uint128 回绕；头寸所有者应在待领取手续费达到上限前完成提取
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}
