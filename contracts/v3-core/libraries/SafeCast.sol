// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 安全类型转换方法
/// @notice 在数值超出目标类型范围时回退，避免截断造成资产计算错误
/// @dev Solidity 0.7 的显式窄化转换会静默截掉高位。例如过大的 uint256 转成 uint160 后可能变成
/// 完全不同的价格。这里通过“转换后再转回并比较”确认数值未变化，特别用于 sqrtPrice、liquidityDelta
/// 和正负 swap 数量等会影响资产转移的字段。
library SafeCast {
    /// @notice 将 uint256 转换为 uint160，超出范围时回退
    /// @param y 待向下转换的 uint256
    /// @return z 转换后的 uint160
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        require((z = uint160(y)) == y);
    }

    /// @notice 将 int256 转换为 int128，溢出或下溢时回退
    /// @param y 待向下转换的 int256
    /// @return z 转换后的 int128
    function toInt128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y);
    }

    /// @notice 将 uint256 转换为 int256，超出 int256 正数范围时回退
    /// @param y 待转换的 uint256
    /// @return z 转换后的 int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
}
