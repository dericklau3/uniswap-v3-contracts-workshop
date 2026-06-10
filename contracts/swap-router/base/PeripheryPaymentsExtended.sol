// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import '../interfaces/IPeripheryPaymentsExtended.sol';

abstract contract PeripheryPaymentsExtended is IPeripheryPaymentsExtended, PeripheryPayments {
    /// @notice 将本合约持有的 WETH9 解包成 ETH 并发送给调用者。
    function unwrapWETH9(uint256 amountMinimum) external payable override {
        unwrapWETH9(amountMinimum, msg.sender);
    }

    /// @notice 把调用随附的 ETH 包装为 WETH9 留在本合约中。
    function wrapETH(uint256 value) external payable override {
        IWETH9(WETH9).deposit{value: value}();
    }

    /// @notice 将本合约持有的指定 ERC20 全部扫给调用者。
    function sweepToken(address token, uint256 amountMinimum) external payable override {
        sweepToken(token, amountMinimum, msg.sender);
    }

    /// @notice 从调用者拉取指定 ERC20 到本合约，常用于后续 multicall 内复用余额。
    function pull(address token, uint256 value) external payable override {
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), value);
    }
}
