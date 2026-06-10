// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '../interfaces/IERC20Minimal.sol';

/// @title 安全转账辅助库
/// @notice 兼容 transfer 返回 true、无返回值或调用失败的不同 ERC20 实现
library TransferHelper {
    /// @notice 将调用方持有的 token 转给接收者
    /// @dev 低级调用 token.transfer；调用失败或显式返回 false 时以 TF 回退
    /// @param token 待转账 ERC20 的合约地址
    /// @param to 接收者地址
    /// @param value 转账数量
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }
}
