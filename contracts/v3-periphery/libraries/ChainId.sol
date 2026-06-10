// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

/// @title 获取当前链 ID 的函数
library ChainId {
    /// @dev 通过 EVM chainid 操作码获取当前链 ID
    /// @return chainId 当前链 ID
    function get() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}
