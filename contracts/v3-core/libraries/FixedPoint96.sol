// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title 96 位二进制定点数常量
/// @notice 提供 Q96 缩放因子，用于表示 Uniswap V3 的 Q64.96 平方根价格
/// @dev `sqrtPriceX96 = sqrt(token1/token0) * 2^96`。要还原普通价格，需要先除以 Q96 再平方。
/// 保存平方根价格可让恒定乘积曲线中的 token 数量变化公式保持线性形式；96 位小数精度兼顾精度与
/// uint160 存储空间，使价格能与其他 `slot0` 字段打包在较少的存储槽中。
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
