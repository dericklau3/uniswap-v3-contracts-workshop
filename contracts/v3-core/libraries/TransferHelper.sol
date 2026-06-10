// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '../interfaces/IERC20Minimal.sol';

/// @title 安全转账辅助库
/// @notice 兼容 transfer 返回 true、无返回值或调用失败的不同 ERC20 实现
/// @dev ERC20 历史实现并不完全统一：标准 token 返回 bool，一些老 token 成功时不返回数据，
/// 失败 token 可能返回 false 或直接 revert。本库把“调用成功且无返回值”和“解码为 true”都视为成功，
/// 其余情况统一回退，避免池已经更新会计状态却没有真正转出资产。
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
