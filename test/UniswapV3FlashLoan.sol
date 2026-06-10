// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3FlashCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import {Errors} from "./lib/Errors.sol";

/// @title Uniswap V3 Flash Loan 模板
/// @notice 从指定 V3 pool 借出单个 token，执行自定义逻辑，归还本息并转出剩余盈利。
contract UniswapV3FlashLoan is IUniswapV3FlashCallback {
    using SafeERC20 for IERC20;

    struct FlashLoanContext {
        address pool;
        address initiator;
        address borrowToken;
        uint256 borrowAmount;
    }

    /// @notice flash loan 结束后接收借入 token 剩余余额的地址。
    address public immutable PROFIT_RECIPIENT;

    FlashLoanContext private context;

    /// @param profitRecipient_ flash loan 盈利接收地址。
    constructor(address profitRecipient_) {
        require(profitRecipient_ != address(0), Errors.ZeroAddress());
        PROFIT_RECIPIENT = profitRecipient_;
    }

    /// @notice 从指定 Uniswap V3 pool 借出单个 token。
    /// @dev `borrowToken` 必须是 pool 的 token0 或 token1，且同一时间只能执行一笔 flash loan。
    /// @param pool 提供 flash loan 的 Uniswap V3 pool。
    /// @param borrowToken 要借出的 token。
    /// @param borrowAmount 要借出的数量。
    function startFlashLoan(address pool, address borrowToken, uint256 borrowAmount) external {
        require(pool != address(0) && borrowToken != address(0), Errors.ZeroAddress());
        require(borrowAmount > 0, Errors.InvalidFlashLoanAmount());
        require(context.pool == address(0), Errors.FlashLoanInProgress());

        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        require(borrowToken == token0 || borrowToken == token1, Errors.InvalidParameter());

        uint256 amount0 = borrowToken == token0 ? borrowAmount : 0;
        uint256 amount1 = borrowToken == token1 ? borrowAmount : 0;

        context =
            FlashLoanContext({pool: pool, initiator: msg.sender, borrowToken: borrowToken, borrowAmount: borrowAmount});

        IUniswapV3Pool(pool).flash(address(this), amount0, amount1, abi.encode(borrowToken, borrowAmount));

        delete context;
    }

    /// @notice V3 pool 发放借款后调用的回调。
    /// @dev 只接受由当前 `startFlashLoan` 指定 pool 发起且参数完全匹配的回调。
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        FlashLoanContext memory currentContext = context;
        require(msg.sender == currentContext.pool, Errors.UnexpectedCallback());
        require(data.length == 64, Errors.UnexpectedCallback());

        (address borrowToken, uint256 borrowAmount) = abi.decode(data, (address, uint256));
        require(
            borrowToken == currentContext.borrowToken && borrowAmount == currentContext.borrowAmount,
            Errors.UnexpectedCallback()
        );

        address token0 = IUniswapV3Pool(msg.sender).token0();
        uint256 fee;
        if (borrowToken == token0) {
            require(fee1 == 0, Errors.UnexpectedCallback());
            fee = fee0;
        } else {
            require(fee0 == 0, Errors.UnexpectedCallback());
            fee = fee1;
        }

        _executeFlashLoan(msg.sender, borrowToken, borrowAmount, fee, currentContext.initiator);

        uint256 repayment = borrowAmount + fee;
        IERC20 token = IERC20(borrowToken);
        require(token.balanceOf(address(this)) >= repayment, Errors.InsufficientRepaymentBalance());
        token.safeTransfer(msg.sender, repayment);

        uint256 profit = token.balanceOf(address(this));
        if (profit > 0) {
            token.safeTransfer(PROFIT_RECIPIENT, profit);
        }
    }

    /// @dev 在这里直接填写套利、清算或其他需要使用 flash loan 资金的原子逻辑。
    function _executeFlashLoan(address pool, address borrowToken, uint256 borrowAmount, uint256 fee, address initiator)
        internal
    {
        pool;
        borrowToken;
        borrowAmount;
        fee;
        initiator;
    }
}
