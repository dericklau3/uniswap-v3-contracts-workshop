// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title 128 位二进制定点数常量
/// @notice 提供 Q128 缩放因子，用于将手续费增长从 Q128 精度换算为 token 数量
/// @dev 链上没有浮点数，因此把真实小数乘以 `2^128` 后存成整数。
/// 例如“每 1 流动性累计 0.5 token 手续费”存为 `0.5 * Q128`；
/// 仓位结算时再乘 liquidity 并除以 Q128，恢复实际 token 数量。高精度可减少大量 swap 累计后的舍入损失。
library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
