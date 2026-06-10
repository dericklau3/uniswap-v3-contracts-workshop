// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '../interfaces/IMulticall.sol';

/// @title 批量调用
/// @notice 允许在同一笔交易里通过 delegatecall 顺序执行多个当前合约方法。
/// @dev 常见组合是 permit -> swap -> unwrapWETH -> refundETH，或建池 -> mint -> 退回剩余资产。
/// 所有子调用共享原始 msg.sender、msg.value 和本合约存储；任一步失败，整组操作原子回退。
abstract contract Multicall is IMulticall {
    /// @notice 批量执行多个 ABI 编码后的函数调用，并返回每个调用的返回数据。
    /// @dev 使用 delegatecall 保持同一个 msg.sender、msg.value 和合约存储上下文。
    function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // 下面几行用于剥离 Error(string) 选择器并透传原始 revert reason。
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
