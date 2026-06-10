// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '../libraries/UniswapV2Library.sol';
import '../interfaces/ISwapRouter02.sol';
import '../interfaces/ITokenValidator.sol';
import '../base/ImmutableState.sol';

/// @notice 通过 V2 的 token/baseToken 池子闪借目标 token，粗略判断 token 转账是否会扣费或失败。
/// @notice 返回 Status.FOT 表示检测到转账扣费，Status.STF 表示 token 转账失败，Status.UNKN 表示无法确认异常。
/// @dev UNKN 不代表 token 一定安全，只代表这次探测没有发现问题。
/// 结果不保证完全准确：有些 token 只在特定地址/条件下扣费，也可能根本没有可用 V2 池子来闪借测试。
contract TokenValidator is ITokenValidator, IUniswapV2Callee, ImmutableState {
    string internal constant FOT_REVERT_STRING = 'FOT';
    // https://github.com/Uniswap/v2-core/blob/1136544ac842ff48ae0b1b939701436598d74075/contracts/UniswapV2Pair.sol#L46
    string internal constant STF_REVERT_STRING_SUFFIX = 'TRANSFER_FAILED';

    constructor(address _factoryV2, address _positionManager) ImmutableState(_factoryV2, _positionManager) {}

    function batchValidate(
        address[] calldata tokens,
        address[] calldata baseTokens,
        uint256 amountToBorrow
    ) public override returns (Status[] memory isFotResults) {
        isFotResults = new Status[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            isFotResults[i] = validate(tokens[i], baseTokens, amountToBorrow);
        }
    }

    function validate(
        address token,
        address[] calldata baseTokens,
        uint256 amountToBorrow
    ) public override returns (Status) {
        for (uint256 i = 0; i < baseTokens.length; i++) {
            Status result = _validate(token, baseTokens[i], amountToBorrow);
            if (result == Status.FOT || result == Status.STF) {
                return result;
            }
        }
        return Status.UNKN;
    }

    function _validate(
        address token,
        address baseToken,
        uint256 amountToBorrow
    ) internal returns (Status) {
        if (token == baseToken) {
            return Status.UNKN;
        }

        address pairAddress = UniswapV2Library.pairFor(this.factoryV2(), token, baseToken);

        // 如果 token/baseToken pair 存在，读取 token0；用底层 call 是为了兼容 pair 不存在的情况。
        (, bytes memory returnData) = address(pairAddress).call(abi.encodeWithSelector(IUniswapV2Pair.token0.selector));

        if (returnData.length == 0) {
            return Status.UNKN;
        }

        address token0Address = abi.decode(returnData, (address));

        // 从 V2 pair 闪借 amountToBorrow 个目标 token。
        (uint256 amount0Out, uint256 amount1Out) =
            token == token0Address ? (amountToBorrow, uint256(0)) : (uint256(0), amountToBorrow);

        uint256 balanceBeforeLoan = IERC20(token).balanceOf(address(this));

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        try
            pair.swap(amount0Out, amount1Out, address(this), abi.encode(balanceBeforeLoan, amountToBorrow))
        {} catch Error(string memory reason) {
            if (isFotFailed(reason)) {
                return Status.FOT;
            }

            if (isTransferFailed(reason)) {
                return Status.STF;
            }

            return Status.UNKN;
        }

        // 回调总会主动 revert 返回探测结果，正常情况下不会走到这里。
        revert('Unexpected error');
    }

    function isFotFailed(string memory reason) internal pure returns (bool) {
        return keccak256(bytes(reason)) == keccak256(bytes(FOT_REVERT_STRING));
    }

    function isTransferFailed(string memory reason) internal pure returns (bool) {
        // 只检查 revert 字符串后缀，兼容修改过前缀的 V2 fork。
        string memory stf = STF_REVERT_STRING_SUFFIX;

        uint256 reasonLength = bytes(reason).length;
        uint256 suffixLength = bytes(stf).length;
        if (reasonLength < suffixLength) {
            return false;
        }

        uint256 ptr;
        uint256 offset = 32 + reasonLength - suffixLength;
        bool transferFailed;
        assembly {
            ptr := add(reason, offset)
            let suffixPtr := add(stf, 32)
            transferFailed := eq(keccak256(ptr, suffixLength), keccak256(suffixPtr, suffixLength))
        }

        return transferFailed;
    }

    function uniswapV2Call(
        address,
        uint256 amount0,
        uint256,
        bytes calldata data
    ) external view override {
        IUniswapV2Pair pair = IUniswapV2Pair(msg.sender);
        (address token0, address token1) = (pair.token0(), pair.token1());

        IERC20 tokenBorrowed = IERC20(amount0 > 0 ? token0 : token1);

        (uint256 balanceBeforeLoan, uint256 amountRequestedToBorrow) = abi.decode(data, (uint256, uint256));
        uint256 amountBorrowed = tokenBorrowed.balanceOf(address(this)) - balanceBeforeLoan;

        // 如果实际收到的 token 少于请求闪借数量，说明转账过程中发生了扣费。
        if (amountBorrowed != amountRequestedToBorrow) {
            revert(FOT_REVERT_STRING);
        }

        // 这里无论如何都主动 revert：如果继续执行，pair 也会因为没归还本金+0.3% 手续费而回滚。
        // 提前回滚可以节省 gas/time，并把“未发现问题”编码为 Unknown。
        revert('Unknown');
    }
}
