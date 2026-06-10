// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title 128 位二进制定点数常量
/// @notice 提供 Q128 缩放因子，用于将手续费增长从 Q128 精度换算为 token 数量
/// @dev 二进制定点数格式参见 https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
