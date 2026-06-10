// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title 96 位二进制定点数常量
/// @notice 提供 Q96 缩放因子，用于表示 Uniswap V3 的 Q64.96 平方根价格
/// @dev 由 SqrtPriceMath.sol 使用；二进制定点数格式参见 https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
