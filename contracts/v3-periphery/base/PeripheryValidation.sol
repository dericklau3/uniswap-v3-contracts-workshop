// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import './BlockTimestamp.sol';

/// @title 外围交易有效期检查
/// @notice 防止用户签署的交易在很久以后、市场价格已明显变化时仍被执行。
/// @dev deadline 只限制时间，不直接限制成交价格；仍需配合最小输出、最大输入等滑点参数。
abstract contract PeripheryValidation is BlockTimestamp {
    modifier checkDeadline(uint256 deadline) {
        require(_blockTimestamp() <= deadline, 'Transaction too old');
        _;
    }
}
