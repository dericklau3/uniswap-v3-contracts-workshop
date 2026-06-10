// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './PoolAddress.sol';

/// @notice 验证回调调用方是否为指定工厂部署的合法 Uniswap V3 池
library CallbackValidation {
    /// @notice 根据两种 token 和费率验证并返回合法池地址
    /// @dev 通过 CREATE2 确定性地址与 msg.sender 比较，阻止伪造池触发支付回调
    /// @param factory Uniswap V3 工厂合约地址
    /// @param tokenA token0 或 token1 的合约地址
    /// @param tokenB 另一种 token 的合约地址
    /// @param fee 池的交换费率，单位为百分之一基点，即百万分之一
    /// @return pool V3 池合约地址
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (IUniswapV3Pool pool) {
        return verifyCallback(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @notice 根据 PoolKey 验证并返回合法池地址
    /// @param factory Uniswap V3 工厂合约地址
    /// @param poolKey 标识 V3 池的有序 token 和费率
    /// @return pool V3 池合约地址
    function verifyCallback(address factory, PoolAddress.PoolKey memory poolKey)
        internal
        view
        returns (IUniswapV3Pool pool)
    {
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        require(msg.sender == address(pool));
    }
}
