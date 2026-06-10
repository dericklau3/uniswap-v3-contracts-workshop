// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

import '../interfaces/IApproveAndCall.sol';
import './ImmutableState.sol';

/// @title 授权并调用
/// @notice 允许调用者让本合约先授权 V3 仓位管理器，再把调用转发给仓位管理器。
/// @dev 主要用于 multicall：先把 token 拉到路由，再授权 positionManager 并 mint/increase。
abstract contract ApproveAndCall is IApproveAndCall, ImmutableState {
    function tryApprove(address token, uint256 amount) private returns (bool) {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, positionManager, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    /// @notice 探测某个 token 对 positionManager 最适合使用哪种 approve 流程。
    /// @dev 兼容部分需要先归零、或不接受 uint256.max 的 ERC20。
    function getApprovalType(address token, uint256 amount) external override returns (ApprovalType) {
        // 先检查当前授权是否已经足够。
        if (IERC20(token).allowance(address(this), positionManager) >= amount) return ApprovalType.NOT_REQUIRED;

        // 尝试最大值和最大值减一，后者兼容少数特殊 token。
        if (tryApprove(token, type(uint256).max)) return ApprovalType.MAX;
        if (tryApprove(token, type(uint256).max - 1)) return ApprovalType.MAX_MINUS_ONE;

        // 有些 token 要求先把 allowance 归零再重新设置。
        require(tryApprove(token, 0));

        // 归零后再次尝试最大值和最大值减一。
        if (tryApprove(token, type(uint256).max)) return ApprovalType.ZERO_THEN_MAX;
        if (tryApprove(token, type(uint256).max - 1)) return ApprovalType.ZERO_THEN_MAX_MINUS_ONE;

        revert();
    }

    /// @notice 授权 positionManager 使用该 token 的最大额度。
    function approveMax(address token) external payable override {
        require(tryApprove(token, type(uint256).max));
    }

    /// @notice 授权 positionManager 使用该 token 的最大额度减一。
    function approveMaxMinusOne(address token) external payable override {
        require(tryApprove(token, type(uint256).max - 1));
    }

    /// @notice 先把该 token 授权清零，再授权最大额度。
    function approveZeroThenMax(address token) external payable override {
        require(tryApprove(token, 0));
        require(tryApprove(token, type(uint256).max));
    }

    /// @notice 先把该 token 授权清零，再授权最大额度减一。
    function approveZeroThenMaxMinusOne(address token) external payable override {
        require(tryApprove(token, 0));
        require(tryApprove(token, type(uint256).max - 1));
    }

    /// @notice 直接调用 positionManager，并在失败时透传 revert reason。
    function callPositionManager(bytes memory data) public payable override returns (bytes memory result) {
        bool success;
        (success, result) = positionManager.call(data);

        if (!success) {
            // 剥离 Error(string) 选择器并透传原始 revert reason。
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
    }

    function balanceOf(address token) private view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice 用本合约当前持有的 token0/token1 余额去 positionManager 铸造 V3 仓位 NFT。
    function mint(MintParams calldata params) external payable override returns (bytes memory result) {
        return
            callPositionManager(
                abi.encodeWithSelector(
                    INonfungiblePositionManager.mint.selector,
                    INonfungiblePositionManager.MintParams({
                        token0: params.token0,
                        token1: params.token1,
                        fee: params.fee,
                        tickLower: params.tickLower,
                        tickUpper: params.tickUpper,
                        amount0Desired: balanceOf(params.token0),
                        amount1Desired: balanceOf(params.token1),
                        amount0Min: params.amount0Min,
                        amount1Min: params.amount1Min,
                        recipient: params.recipient,
                        deadline: type(uint256).max // deadline 应由外层 multicall 统一检查。
                    })
                )
            );
    }

    /// @notice 用本合约当前持有的 token0/token1 余额给已有 V3 仓位增加流动性。
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        returns (bytes memory result)
    {
        return
            callPositionManager(
                abi.encodeWithSelector(
                    INonfungiblePositionManager.increaseLiquidity.selector,
                    INonfungiblePositionManager.IncreaseLiquidityParams({
                        tokenId: params.tokenId,
                        amount0Desired: balanceOf(params.token0),
                        amount1Desired: balanceOf(params.token1),
                        amount0Min: params.amount0Min,
                        amount1Min: params.amount1Min,
                        deadline: type(uint256).max // deadline 应由外层 multicall 统一检查。
                    })
                )
            );
    }
}
