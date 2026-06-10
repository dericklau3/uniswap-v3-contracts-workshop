// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Core Pool 仓位键计算
/// @notice 复现 Pool 的 `keccak256(owner, tickLower, tickUpper)`，用于查询底层 Position.Info。
/// @dev PositionManager 以自身地址作为 owner，因此多个 NFT 的外围账目由 Manager 另行分配。
library PositionKey {
    /// @dev 返回 core 池中由所有者和上下 tick 唯一确定的头寸键
    function compute(
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }
}
