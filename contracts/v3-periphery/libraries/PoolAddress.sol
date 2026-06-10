// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 根据工厂、token 和费率推导池地址
/// @notice 对 token 排序并复现 Factory 的 CREATE2 地址公式，无需外部查询注册表。
/// @dev 计算结果只说明“若部署会在这个地址”，不保证该地址已有代码。
/// Router 在预期池存在的路径中使用它，同时 callback 验证也依赖同一确定性地址。
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0x6d8d409b721a2b71d4cb7bf5c497b0543bc2e1d16957e92e8ff8265cdd33c512;

    /// @notice 唯一标识池的有序 token 对和费率
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
    }

    /// @notice 将两个 token 按地址排序并组成 PoolKey
    /// @param tokenA 未排序的第一个 token
    /// @param tokenB 未排序的第二个 token
    /// @param fee 池费率等级
    /// @return Poolkey 包含有序 token0、token1 和费率的池标识
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice 根据工厂地址和 PoolKey 确定性计算池地址
    /// @dev 使用 CREATE2 公式，无需外部调用工厂查询
    /// @param factory Uniswap V3 工厂合约地址
    /// @param key 池的 PoolKey
    /// @return pool V3 池合约地址
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        );
    }
}
