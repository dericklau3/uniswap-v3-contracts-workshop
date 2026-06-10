// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Workshop 错误定义
/// @notice 集中定义测试目录示例合约使用的自定义错误。
library Errors {
    error ZeroAddress();
    error InvalidToken();
    error InvalidPool();
    error InvalidParameter();
    error InvalidFlashLoanAmount();
    error FlashLoanInProgress();
    error UnexpectedCallback();
    error InsufficientRepaymentBalance();
    error PoolNotConfigured(address token);
    error UnsupportedDecimals(address token, uint8 decimals);
}
