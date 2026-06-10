// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/base/SelfPermit.sol';
import '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';

import './interfaces/ISwapRouter02.sol';
import './V2SwapRouter.sol';
import './V3SwapRouter.sol';
import {ApproveAndCall} from './base/ApproveAndCall.sol';
import './base/MulticallExtended.sol';

/// @title Uniswap V2/V3 聚合兑换路由
/// @notice 把 V2 swap、V3 swap、permit、支付清算、PositionManager 调用和扩展 multicall 组合到一个入口。
/// @dev 用户可在一笔 multicall 中拉入资产、经过 V2/V3 多池兑换、把中间余额用于加仓，
/// 最后 sweep 或 unwrap 给自己。聚合只共享入口和支付工具，不会混淆 V2 储备模型与 V3 集中流动性数学。
contract SwapRouter02 is ISwapRouter02, V2SwapRouter, V3SwapRouter, ApproveAndCall, MulticallExtended, SelfPermit {
    constructor(
        address _factoryV2,
        address factoryV3,
        address _positionManager,
        address _WETH9
    ) ImmutableState(_factoryV2, _positionManager) PeripheryImmutableState(factoryV3, _WETH9) {}
}
