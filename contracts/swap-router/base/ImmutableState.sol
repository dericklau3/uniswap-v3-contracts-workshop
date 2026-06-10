// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../interfaces/IImmutableState.sol';

/// @title 路由不可变状态
/// @notice 保存 swap-router 共同依赖的 V2 工厂和 V3 仓位管理器地址。
/// @dev V2 Factory 用于推导 Pair，PositionManager 用于把 Router 中间余额转成 V3 NFT 仓位。
/// 地址不可变可避免用户授权后资金接收方被替换。
abstract contract ImmutableState is IImmutableState {
    /// @notice Uniswap V2 工厂合约地址。
    address public immutable override factoryV2;
    /// @notice Uniswap V3 NonfungiblePositionManager 地址。
    address public immutable override positionManager;

    constructor(address _factoryV2, address _positionManager) {
        factoryV2 = _factoryV2;
        positionManager = _positionManager;
    }
}
