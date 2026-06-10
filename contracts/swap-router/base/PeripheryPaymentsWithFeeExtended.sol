// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@uniswap/v3-periphery/contracts/base/PeripheryPaymentsWithFee.sol';

import '../interfaces/IPeripheryPaymentsWithFeeExtended.sol';
import './PeripheryPaymentsExtended.sol';

/// @title 面向调用者的带费清算快捷入口
/// @notice 复用基础 fee 清算逻辑，并把扣费后的剩余资产 recipient 固定为 msg.sender。
/// @dev 常放在 multicall 末尾，对最终 WETH/ETH 或 ERC20 结果收取聚合服务费。
abstract contract PeripheryPaymentsWithFeeExtended is
    IPeripheryPaymentsWithFeeExtended,
    PeripheryPaymentsExtended,
    PeripheryPaymentsWithFee
{
    /// @notice 将本合约 WETH9 解包为 ETH，抽取费用后把剩余 ETH 发送给调用者。
    function unwrapWETH9WithFee(
        uint256 amountMinimum,
        uint256 feeBips,
        address feeRecipient
    ) external payable override {
        unwrapWETH9WithFee(amountMinimum, msg.sender, feeBips, feeRecipient);
    }

    /// @notice 将本合约持有的 ERC20 扫给调用者，并从中抽取费用。
    function sweepTokenWithFee(
        address token,
        uint256 amountMinimum,
        uint256 feeBips,
        address feeRecipient
    ) external payable override {
        sweepTokenWithFee(token, amountMinimum, msg.sender, feeBips, feeRecipient);
    }
}
