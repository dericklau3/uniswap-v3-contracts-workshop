// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

/// @title 低 gas 的安全数学运算
/// @notice 以较低 gas 成本执行算术，并在溢出或下溢时回退
/// @dev 这些合约固定在 Solidity 0.7.x，编译器尚不会自动检查整数溢出。
/// 库只实现核心热路径需要的少量操作，避免引入更大通用库；Solidity 0.8+ 中多数场景可用内置检查替代。
library LowGasSafeMath {
    /// @notice 返回 x + y，uint256 加法溢出时回退
    /// @param x 被加数
    /// @param y 加数
    /// @return z 两数之和
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    /// @notice 返回 x - y，下溢时回退
    /// @param x 被减数
    /// @param y 减数
    /// @return z 两数之差
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    /// @notice 返回 x * y，溢出时回退
    /// @param x 被乘数
    /// @param y 乘数
    /// @return z 两数之积
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    /// @notice 返回 x + y，int256 溢出或下溢时回退
    /// @param x 被加数
    /// @param y 加数
    /// @return z 两数之和
    function add(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x == (y >= 0));
    }

    /// @notice 返回 x - y，int256 溢出或下溢时回退
    /// @param x 被减数
    /// @param y 减数
    /// @return z 两数之差
    function sub(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x - y) <= x == (y >= 0));
    }
}
