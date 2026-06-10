// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3FlashCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import {UniswapV3FlashLoan} from "./UniswapV3FlashLoan.sol";
import {Errors} from "./lib/Errors.sol";

contract UniswapV3FlashLoanTest is Test {
    uint256 internal constant BORROW_AMOUNT = 100 ether;
    uint256 internal constant FLASH_FEE = 0.3 ether;
    uint256 internal constant PROFIT = 5 ether;

    address internal profitRecipient = makeAddr("profitRecipient");
    MockFlashToken internal token0;
    MockFlashToken internal token1;
    MockUniswapV3FlashPool internal pool;
    UniswapV3FlashLoan internal flashLoan;

    function setUp() public {
        token0 = new MockFlashToken("Token 0", "TK0");
        token1 = new MockFlashToken("Token 1", "TK1");
        pool = new MockUniswapV3FlashPool(address(token0), address(token1), FLASH_FEE);
        flashLoan = new UniswapV3FlashLoan(profitRecipient);

        token0.mint(address(pool), 1_000 ether);
        token1.mint(address(pool), 1_000 ether);
    }

    function test_ConstructorSetsProfitRecipient() public view {
        assertEq(flashLoan.PROFIT_RECIPIENT(), profitRecipient);
    }

    function test_ConstructorRevertsForZeroProfitRecipient() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new UniswapV3FlashLoan(address(0));
    }

    function test_StartFlashLoanBorrowsToken0RepaysFeeAndTransfersProfit() public {
        token0.mint(address(flashLoan), FLASH_FEE + PROFIT);
        uint256 poolBalanceBefore = token0.balanceOf(address(pool));

        flashLoan.startFlashLoan(address(pool), address(token0), BORROW_AMOUNT);

        assertEq(token0.balanceOf(address(pool)), poolBalanceBefore + FLASH_FEE);
        assertEq(token0.balanceOf(profitRecipient), PROFIT);
        assertEq(token0.balanceOf(address(flashLoan)), 0);
        assertEq(pool.lastAmount0(), BORROW_AMOUNT);
        assertEq(pool.lastAmount1(), 0);
    }

    function test_StartFlashLoanBorrowsToken1RepaysFeeAndTransfersProfit() public {
        token1.mint(address(flashLoan), FLASH_FEE + PROFIT);
        uint256 poolBalanceBefore = token1.balanceOf(address(pool));

        flashLoan.startFlashLoan(address(pool), address(token1), BORROW_AMOUNT);

        assertEq(token1.balanceOf(address(pool)), poolBalanceBefore + FLASH_FEE);
        assertEq(token1.balanceOf(profitRecipient), PROFIT);
        assertEq(token1.balanceOf(address(flashLoan)), 0);
        assertEq(pool.lastAmount0(), 0);
        assertEq(pool.lastAmount1(), BORROW_AMOUNT);
    }

    function test_StartFlashLoanRevertsForZeroPool() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        flashLoan.startFlashLoan(address(0), address(token0), BORROW_AMOUNT);
    }

    function test_StartFlashLoanRevertsForZeroToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        flashLoan.startFlashLoan(address(pool), address(0), BORROW_AMOUNT);
    }

    function test_StartFlashLoanRevertsForZeroAmount() public {
        vm.expectRevert(Errors.InvalidFlashLoanAmount.selector);
        flashLoan.startFlashLoan(address(pool), address(token0), 0);
    }

    function test_StartFlashLoanRevertsForTokenOutsidePool() public {
        MockFlashToken otherToken = new MockFlashToken("Other", "OTHER");

        vm.expectRevert(Errors.InvalidParameter.selector);
        flashLoan.startFlashLoan(address(pool), address(otherToken), BORROW_AMOUNT);
    }

    function test_StartFlashLoanRevertsWhenLoanIsAlreadyInProgress() public {
        pool.setReenter(true);

        vm.expectRevert(Errors.FlashLoanInProgress.selector);
        flashLoan.startFlashLoan(address(pool), address(token0), BORROW_AMOUNT);
    }

    function test_FlashCallbackRevertsWhenCalledWithoutActiveLoan() public {
        vm.expectRevert(Errors.UnexpectedCallback.selector);
        flashLoan.uniswapV3FlashCallback(FLASH_FEE, 0, abi.encode(address(token0), BORROW_AMOUNT));
    }

    function test_FlashCallbackRevertsWhenPoolChangesCallbackData() public {
        pool.setCorruptCallbackData(true);

        vm.expectRevert(Errors.UnexpectedCallback.selector);
        flashLoan.startFlashLoan(address(pool), address(token0), BORROW_AMOUNT);
    }

    function test_FlashCallbackRevertsForInsufficientRepaymentBalance() public {
        vm.expectRevert(Errors.InsufficientRepaymentBalance.selector);
        flashLoan.startFlashLoan(address(pool), address(token0), BORROW_AMOUNT);
    }
}

contract MockFlashToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

interface IFlashLoanStarter {
    function startFlashLoan(address pool, address borrowToken, uint256 borrowAmount) external;
}

contract MockUniswapV3FlashPool {
    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;
    uint256 public immutable flashFee;

    uint256 public lastAmount0;
    uint256 public lastAmount1;
    bool public reenter;
    bool public corruptCallbackData;

    constructor(address token0_, address token1_, uint256 flashFee_) {
        token0 = token0_;
        token1 = token1_;
        flashFee = flashFee_;
    }

    function setReenter(bool reenter_) external {
        reenter = reenter_;
    }

    function setCorruptCallbackData(bool corruptCallbackData_) external {
        corruptCallbackData = corruptCallbackData_;
    }

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external {
        lastAmount0 = amount0;
        lastAmount1 = amount1;

        if (reenter) {
            IFlashLoanStarter(msg.sender).startFlashLoan(address(this), token0, 1);
        }

        address borrowedToken = amount0 > 0 ? token0 : token1;
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        uint256 balanceBefore = IERC20(borrowedToken).balanceOf(address(this));

        IERC20(borrowedToken).safeTransfer(recipient, borrowedAmount);

        bytes memory callbackData = corruptCallbackData ? abi.encode(borrowedToken, borrowedAmount + 1) : data;
        IUniswapV3FlashCallback(msg.sender)
            .uniswapV3FlashCallback(amount0 > 0 ? flashFee : 0, amount1 > 0 ? flashFee : 0, callbackData);

        assert(IERC20(borrowedToken).balanceOf(address(this)) >= balanceBefore + flashFee);
    }
}
