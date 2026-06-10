// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../interfaces/IPeripheryImmutableState.sol';

/// @title 外围合约不可变状态
/// @notice 保存外围合约共同依赖的 V3 工厂地址和 WETH9 地址。
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @notice Uniswap V3 工厂合约地址。
    address public immutable override factory;
    /// @notice WETH9 合约地址，用于 ETH/WETH 包装和解包。
    address public immutable override WETH9;

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }
}
