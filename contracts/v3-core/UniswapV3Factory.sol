// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

/// @title Uniswap V3 官方工厂合约
/// @notice 负责创建 V3 池子，并管理池子协议费相关的 owner 权限。
contract UniswapV3Factory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    /// @notice 工厂管理员地址，可开启新的手续费档位并管理池子的协议费参数。
    address public override owner;

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(UniswapV3Pool).creationCode));

    /// @notice 手续费档位到 tickSpacing 的映射；未启用的手续费档位对应 0。
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @notice 查询某两个代币在指定手续费档位下的池子地址，两个代币顺序都可查到同一个池子。
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // 0.05% swap fee
        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        // 0.3% swap fee
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        // 1% swap fee
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @notice 为一对代币和一个已启用手续费档位创建唯一的 V3 池子。
    /// @dev 代币会按地址排序为 token0/token1；同一 token0/token1/fee 只能创建一次。
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // 反向也写入同一个池子地址，外部查询时无需先比较代币地址大小。
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @notice 转移工厂 owner 权限。
    /// @dev 只有当前 owner 可以调用。
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @notice 启用新的手续费档位及其对应的 tickSpacing。
    /// @dev 手续费档位一旦启用不能关闭或修改；tickSpacing 越大，可用价格刻度越稀疏。
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        // tick 会参与很多底层计算
        // tick 会被压缩后放进 bitmap 里，用于快速查找下一个初始化过的 tick。
        // 如果 tickSpacing 设置得过大，会让 tick 粒度非常粗，而且可能影响 tick bitmap、流动性上限、边界 tick 计算等底层逻辑的安全性。
        // 16384 = 2^14. 这个值不是业务上的推荐配置，而是协议层给的最大安全边界
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
