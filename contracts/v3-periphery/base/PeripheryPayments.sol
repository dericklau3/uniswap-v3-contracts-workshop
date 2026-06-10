// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../interfaces/IPeripheryPayments.sol';
import '../interfaces/external/IWETH9.sol';

import '../libraries/TransferHelper.sol';

import './PeripheryImmutableState.sol';

abstract contract PeripheryPayments is IPeripheryPayments, PeripheryImmutableState {
    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @notice 将本合约持有的 WETH9 解包成 ETH 并发送给 recipient。
    /// @dev amountMinimum 是防止余额不足或被提前取走的保护，常用于 multicall 末尾清算。
    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable override {
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        require(balanceWETH9 >= amountMinimum, 'Insufficient WETH9');

        if (balanceWETH9 > 0) {
            IWETH9(WETH9).withdraw(balanceWETH9);
            TransferHelper.safeTransferETH(recipient, balanceWETH9);
        }
    }

    /// @notice 将本合约持有的某个 ERC20 全部扫给 recipient。
    /// @dev amountMinimum 用作最小余额保护，避免用户期望的中间资产不足。
    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) public payable override {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, 'Insufficient token');

        if (balanceToken > 0) {
            TransferHelper.safeTransfer(token, recipient, balanceToken);
        }
    }

    /// @notice 退还本合约当前持有的所有 ETH 给调用者。
    function refundETH() external payable override {
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token 要支付的代币。
    /// @param payer 资金来源地址；可以是用户，也可以是当前合约。
    /// @param recipient 收款地址，通常是 pool 或 pair。
    /// @param value 支付数量。
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // 用本合约持有的 ETH 包装成 WETH9，只包装本次实际需要支付的数量。
            IWETH9(WETH9).deposit{value: value}();
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // 用本合约已经持有的 token 支付，常见于精确输入多跳的中间资产。
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // 从用户或指定 payer 拉取 token。
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
