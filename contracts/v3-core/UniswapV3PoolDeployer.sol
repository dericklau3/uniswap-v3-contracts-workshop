// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';

import './UniswapV3Pool.sol';

/// @title V3 Pool 的确定性部署辅助合约
/// @notice 用 CREATE2 部署池，并在构造期间向新池传递 factory、token、fee 与 tickSpacing。
/// @dev Pool creationCode 对所有市场都相同，若把构造参数直接编码进 init code，不同参数会改变代码哈希，
/// 不利于统一推导地址。这里先把参数暂存在 deployer 存储中，新 Pool 构造函数通过 `msg.sender.parameters()`
/// 读取，随后立即删除。这样所有池共享同一个 init code hash，地址只由 factory、salt 和代码哈希决定。
///
/// 该临时状态只存在于同一笔同步部署调用中。Pool 构造完成前 `new` 不会返回，外部也不能插入另一笔部署。
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
