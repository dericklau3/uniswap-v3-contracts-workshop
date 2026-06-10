// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';

import './UniswapV3Pool.sol';

contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @notice 临时保存正在部署的池子参数，供 UniswapV3Pool 构造函数读取。
    /// @dev deploy 完成后会立刻 delete，避免参数被后续部署误用。
    Parameters public override parameters;

    /// @dev 通过临时写入 parameters 部署池子，让新池子构造函数能读取工厂、代币和费率信息。
    /// @param factory Uniswap V3 工厂合约地址。
    /// @param token0 按地址排序后的第一个代币。
    /// @param token1 按地址排序后的第二个代币。
    /// @param fee 池子每笔 swap 收取的手续费，单位是百万分之一。
    /// @param tickSpacing 可用 tick 之间的间隔。
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal returns (address pool) {
        parameters = Parameters({factory: factory, token0: token0, token1: token1, fee: fee, tickSpacing: tickSpacing});
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        delete parameters;
    }
}
