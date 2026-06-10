// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './PeripheryImmutableState.sol';
import '../interfaces/IPoolInitializer.sol';

/// @title 创建并初始化 V3 池子
/// @notice 把“查池、必要时建池、必要时设置首价”合并为幂等流程。
/// @dev 常用于首次加仓前：池不存在则创建，存在但价格为 0 则初始化，已初始化则保持市场价格不变。
/// 初始价格只能填补空白市场，不能借此覆盖既有池的价格。
abstract contract PoolInitializer is IPoolInitializer, PeripheryImmutableState {
    /// @notice 如果池子不存在则创建；如果池子尚未初始化则用给定价格初始化。
    /// @dev token0 必须小于 token1；已存在且已初始化的池子会直接返回地址。
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        require(token0 < token1);
        pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = IUniswapV3Factory(factory).createPool(token0, token1, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}
