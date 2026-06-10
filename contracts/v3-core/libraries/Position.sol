// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title LP 区间头寸账本
/// @notice 记录某个 owner 在 `[tickLower, tickUpper)` 区间拥有的流动性和可领取手续费。
/// @dev Core 层没有 NFT，也不知道 PositionManager 的 tokenId。这里使用
/// `keccak256(owner, tickLower, tickUpper)` 作为唯一键，所以同一 owner 对同一区间反复加仓，
/// 实际是在更新同一份 `Info`；外围 PositionManager 则让每个 NFT 自己成为 core 层的 owner，
/// 再在外围账本中把 tokenId 映射到具体用户。
///
/// 手续费采用“累计值减快照”的方式结算，而不是每次 swap 遍历所有 LP：
/// - 池持续更新区间内每单位流动性的累计手续费；
/// - 仓位只保存上次结算时的累计值；
/// - 下次触碰仓位时，用累计值之差乘以旧流动性，得到这段时间应赚的手续费。
/// 这样一笔 swap 的成本与 LP 数量无关，是 V3 能支持大量离散仓位的关键。
library Position {
    /// @notice 单个 owner + 价格区间的会计状态。
    struct Info {
        // 该头寸拥有的流动性份额；它不是 token 数量，需结合当前价格和区间才能换算资产。
        uint128 liquidity;
        // 上次结算时，区间内 token0/token1 的“每单位流动性累计手续费”快照，采用 Q128。
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // 已经结算但尚未 collect 的 token0/token1；减仓得到的本金也会被记入同类待领取余额。
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
    /// @dev 顺序必须是“旧流动性结算历史收益 -> 更新快照 -> 应用流动性变化”。
    /// 例如仓位原有 100 流动性，本次再加 50：过去手续费只能乘 100，新加入的 50 不能分享历史收益。
    /// 反过来减仓时，也要先让即将移除的流动性拿到截至减仓时应得的手续费。
    ///
    /// `liquidityDelta == 0` 是有意支持的“只结算、不加减仓”路径，外围合约可借此刷新手续费。
    /// 但空仓不能这样调用，否则任何人都能无意义地创建和触碰零头寸，因此会以 `NP` 回退。
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

        // 差值是“每 1 单位流动性新增多少手续费”；乘旧 liquidity 后再除 Q128 得到真实 token 数量。
        // Solidity 0.7 的无检查减法在这里是协议设计的一部分：全局累计值允许自然回绕，
        // 只要两次快照之间没有跨越超过完整 uint256 周期，模运算差值仍然正确。
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

        // 先前计算使用的是 _self.liquidity，因此现在才安全地写入新流动性和最新手续费快照。
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
