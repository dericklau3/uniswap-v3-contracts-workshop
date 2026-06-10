// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

/// @title NFT 展示中的 base/quote 排序优先级
/// @notice 为常见稳定币、WETH 和 BTC 包装资产提供可读性更好的价格展示方向权重。
/// @dev 这些常量只影响 tokenURI 中显示“1 个谁等于多少谁”，不改变 Pool 内 token0/token1 排序或成交价格。
library TokenRatioSortOrder {
    int256 constant NUMERATOR_MOST = 300;
    int256 constant NUMERATOR_MORE = 200;
    int256 constant NUMERATOR = 100;

    int256 constant DENOMINATOR_MOST = -300;
    int256 constant DENOMINATOR_MORE = -200;
    int256 constant DENOMINATOR = -100;
}
