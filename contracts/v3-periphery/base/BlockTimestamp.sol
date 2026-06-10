// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

/// @title 区块时间戳读取函数
/// @notice 给 deadline、permit 和 oracle 相关逻辑提供统一的当前时间入口。
/// @dev 生产环境返回 `block.timestamp`；测试合约可重写它来模拟过期、同区块调用和时间推进。
abstract contract BlockTimestamp {
    /// @dev 这个方法主要为了测试可重写，生产环境直接返回 block.timestamp。
    /// @return 当前区块时间戳。
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
