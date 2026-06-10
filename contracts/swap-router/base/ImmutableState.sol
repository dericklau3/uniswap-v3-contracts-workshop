// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../interfaces/IImmutableState.sol';

/// @title 路由不可变状态
/// @notice 保存 swap-router 共同依赖的 V2 工厂和 V3 仓位管理器地址。
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
