// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import './BytesLib.sol';

/// @title 多跳交换路径数据处理函数
/// @notice 编解码紧凑的 `token + fee + token + fee + token...` 路径。
/// @dev 地址占 20 字节，V3 fee 占 3 字节，紧凑 bytes 比结构体数组节省 calldata gas。
/// 精确输入按成交方向编码；精确输出为从最后一跳反推输入，通常反向编码。
/// Router 用 `getFirstPool` 读取当前跳，再用 `skipToken` 推进路径。
library Path {
    using BytesLib for bytes;

    /// @dev bytes 编码地址的长度
    uint256 private constant ADDR_SIZE = 20;
    /// @dev bytes 编码费率的长度
    uint256 private constant FEE_SIZE = 3;

    /// @dev 一个 token 地址与紧随其后的池费率所占长度
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
    /// @dev 单个池段 tokenA + fee + tokenB 的编码长度
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
    /// @dev 包含至少两个池的路径最小编码长度
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice 判断路径是否包含两个或更多池
    /// @param path 编码后的交换路径
    /// @return 包含两个或更多池时为 true，否则为 false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice 返回路径中的池数量
    /// @param path 编码后的交换路径
    /// @return 路径中的池数量
    function numPools(bytes memory path) internal pure returns (uint256) {
        // 忽略第一个 token 地址，之后每组 fee + token 地址代表一个池
        return ((path.length - ADDR_SIZE) / NEXT_OFFSET);
    }

    /// @notice 解码路径中的第一个池
    /// @param path bytes 编码的交换路径
    /// @return tokenA 该池的第一个 token
    /// @return tokenB 该池的第二个 token
    /// @return fee 该池的费率等级
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenA,
            address tokenB,
            uint24 fee
        )
    {
        tokenA = path.toAddress(0);
        fee = path.toUint24(ADDR_SIZE);
        tokenB = path.toAddress(NEXT_OFFSET);
    }

    /// @notice 获取路径中第一个池对应的编码片段
    /// @param path bytes 编码的交换路径
    /// @return 定位第一个池所需的 tokenA、fee 和 tokenB 数据
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice 跳过第一个 token + fee，返回从下一个 token 开始的剩余路径
    /// @param path 交换路径
    /// @return 剩余的 token 和 fee 编码
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }
}
