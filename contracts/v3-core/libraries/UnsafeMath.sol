// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 不检查输入输出的数学函数
/// @notice 提供由调用方保证前置条件的常用数学运算，不执行额外溢出或下溢检查
/// @dev “Unsafe”表示前置条件由上层数学函数证明，并非允许随意传入不可信值。
/// 省去重复检查可降低 swap 热路径 gas；若脱离原调用关系复用，必须重新确认除数非零和数值范围。
library UnsafeMath {
    /// @notice 返回 ceil(x / y)
    /// @dev 除以 0 的行为未定义，必须由调用方提前检查
    /// @param x 被除数
    /// @param y 除数
    /// @return z 向上取整后的商
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }
}
