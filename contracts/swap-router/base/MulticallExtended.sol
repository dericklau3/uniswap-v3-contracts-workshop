// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/base/Multicall.sol';

import '../interfaces/IMulticallExtended.sol';
import '../base/PeripheryValidationExtended.sol';

/// @title 扩展 Multicall
/// @notice 在普通批量调用之外，增加 deadline 和 previousBlockhash 两种保护。
/// @dev deadline 防止长期挂单；previousBlockhash 把执行绑定到紧邻某个已知区块之后。
/// 两种入口最终都复用基础 multicall 的原子 delegatecall 序列。
abstract contract MulticallExtended is IMulticallExtended, Multicall, PeripheryValidationExtended {
    /// @notice 在 deadline 未过期时批量执行多个调用。
    function multicall(uint256 deadline, bytes[] calldata data)
        external
        payable
        override
        checkDeadline(deadline)
        returns (bytes[] memory)
    {
        return multicall(data);
    }

    /// @notice 在上一个区块哈希符合预期时批量执行多个调用。
    /// @dev 用于降低交易在不同区块环境下被执行的风险。
    function multicall(bytes32 previousBlockhash, bytes[] calldata data)
        external
        payable
        override
        checkPreviousBlockhash(previousBlockhash)
        returns (bytes[] memory)
    {
        return multicall(data);
    }
}
