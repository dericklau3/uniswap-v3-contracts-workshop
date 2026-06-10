// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

/// @title 区块时间戳读取函数
/// @dev 测试合约会重写该函数来模拟时间推进。
abstract contract BlockTimestamp {
    /// @dev 这个方法主要为了测试可重写，生产环境直接返回 block.timestamp。
    /// @return 当前区块时间戳。
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
