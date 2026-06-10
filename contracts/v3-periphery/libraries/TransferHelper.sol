// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

library TransferHelper {
    /// @notice 从指定地址向目标地址转移 token
    /// @dev transferFrom 失败时以 STF 回退
    /// @param token 待转账 token 的合约地址
    /// @param from token 来源地址
    /// @param to token 接收地址
    /// @param value 转账数量
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice 将当前合约持有的 token 转给接收者
    /// @dev transfer 失败时以 ST 回退
    /// @param token 待转账 token 的合约地址
    /// @param to 接收者地址
    /// @param value 转账数量
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice 授权指定地址花费给定数量的 token
    /// @dev approve 失败时以 SA 回退
    /// @param token 待授权 token 的合约地址
    /// @param to 被授权地址
    /// @param value 允许被授权地址花费的数量
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice 向接收者地址转移 ETH
    /// @dev ETH 发送失败时以 STE 回退
    /// @param to 接收者地址
    /// @param value ETH 转账数量
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}
