// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

/// @title 获取当前链 ID 的函数
/// @notice 通过 EVM `chainid` 操作码读取签名域所绑定的网络。
/// @dev ERC721 permit 把链 ID 放入 EIP-712 domain，防止一条链上的授权签名被直接拿到另一条链重放。
library ChainId {
    /// @dev 通过 EVM chainid 操作码获取当前链 ID
    /// @return chainId 当前链 ID
    function get() internal pure returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}
