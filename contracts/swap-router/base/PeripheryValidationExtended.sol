// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '@uniswap/v3-periphery/contracts/base/PeripheryValidation.sol';

/// @title 区块环境校验扩展
/// @notice 要求当前交易紧跟在调用者指定的 previousBlockhash 之后执行。
/// @dev 若交易延迟到更晚区块，上一区块哈希会变化并触发回退，避免依赖旧市场状态的组合交易继续执行。
abstract contract PeripheryValidationExtended is PeripheryValidation {
    modifier checkPreviousBlockhash(bytes32 previousBlockhash) {
        require(blockhash(block.number - 1) == previousBlockhash, 'Blockhash');
        _;
    }
}
