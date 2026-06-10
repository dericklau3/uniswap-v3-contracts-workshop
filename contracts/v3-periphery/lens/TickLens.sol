// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import '../interfaces/ITickLens.sol';

/// @title Tick 查询 Lens 合约
contract TickLens is ITickLens {
    /// @notice 读取某个 tickBitmap word 中所有已初始化 tick 及其流动性信息。
    /// @dev 前端可用它批量展开 tick 位图，避免逐个 tick 查询。
    function getPopulatedTicksInWord(address pool, int16 tickBitmapIndex)
        public
        view
        override
        returns (PopulatedTick[] memory populatedTicks)
    {
        // 读取指定 word 的 tick 位图。
        uint256 bitmap = IUniswapV3Pool(pool).tickBitmap(tickBitmapIndex);

        // 先统计已初始化 tick 数量，以便一次性分配返回数组。
        uint256 numberOfPopulatedTicks;
        for (uint256 i = 0; i < 256; i++) {
            if (bitmap & (1 << i) > 0) numberOfPopulatedTicks++;
        }

        // 遍历位图，把已初始化 tick 的 liquidityGross/liquidityNet 取出来。
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        populatedTicks = new PopulatedTick[](numberOfPopulatedTicks);
        for (uint256 i = 0; i < 256; i++) {
            if (bitmap & (1 << i) > 0) {
                int24 populatedTick = ((int24(tickBitmapIndex) << 8) + int24(i)) * tickSpacing;
                (uint128 liquidityGross, int128 liquidityNet, , , , , , ) = IUniswapV3Pool(pool).ticks(populatedTick);
                populatedTicks[--numberOfPopulatedTicks] = PopulatedTick({
                    tick: populatedTick,
                    liquidityNet: liquidityNet,
                    liquidityGross: liquidityGross
                });
            }
        }
    }
}
