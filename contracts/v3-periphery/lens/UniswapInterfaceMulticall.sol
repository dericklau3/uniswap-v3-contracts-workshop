// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

/// @title 前端批量只读调用聚合器
/// @notice 专为 Uniswap Interface 定制的 Multicall2 分支。
/// @dev 它对多个任意 target 分别执行 call，记录成功状态、gasUsed 和返回数据。
/// 单个调用失败不会使整批回退，前端可以在同一 blockNumber 下获得相对一致的池、余额和 token 快照。
/// 这与 Router 的原子 Multicall 不同：这里主要用于读取，允许部分失败，也不会共享业务调用上下文。
contract UniswapInterfaceMulticall {
    struct Call {
        address target;
        uint256 gasLimit;
        bytes callData;
    }

    struct Result {
        bool success;
        uint256 gasUsed;
        bytes returnData;
    }

    function getCurrentBlockTimestamp() public view returns (uint256 timestamp) {
        timestamp = block.timestamp;
    }

    function getEthBalance(address addr) public view returns (uint256 balance) {
        balance = addr.balance;
    }

    function multicall(Call[] memory calls) public returns (uint256 blockNumber, Result[] memory returnData) {
        blockNumber = block.number;
        returnData = new Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (address target, uint256 gasLimit, bytes memory callData) =
                (calls[i].target, calls[i].gasLimit, calls[i].callData);
            uint256 gasLeftBefore = gasleft();
            (bool success, bytes memory ret) = target.call{gas: gasLimit}(callData);
            uint256 gasUsed = gasLeftBefore - gasleft();
            returnData[i] = Result(success, gasUsed, ret);
        }
    }
}
