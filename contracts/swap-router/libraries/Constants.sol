// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

/// @title 路由器状态常量
/// @notice 交换路由器用于压缩调用参数和表达特殊地址语义的常量
library Constants {
    /// @dev 表示本次操作应使用当前合约持有的全部 token 余额
    uint256 internal constant CONTRACT_BALANCE = 0;

    /// @dev msg.sender 的哨兵地址；使用更多零字节可降低 calldata gas
    address internal constant MSG_SENDER = address(1);

    /// @dev address(this) 的哨兵地址；使用更多零字节可降低 calldata gas
    address internal constant ADDRESS_THIS = address(2);
}
