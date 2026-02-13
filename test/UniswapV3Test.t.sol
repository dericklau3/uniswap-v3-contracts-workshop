// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../contracts/v3-core/libraries/FullMath.sol";
import "../contracts/v3-periphery/interfaces/IQuoter.sol";
import "../contracts/v3-periphery/interfaces/ISwapRouter.sol";
import "../contracts/v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract UniswapV3Test is Test {
    address account = makeAddr("account");
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    IQuoter v3Quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address token0;
    address token1;

    uint24 constant FEE = 3000;
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    function setUp() public {
        vm.createSelectFork("mainnet", 24361930);

        tokenA = new MockERC20("Mock Token A", "MTA");
        tokenB = new MockERC20("Mock Token B", "MTB");
        tokenC = new MockERC20("Mock Token C", "MTC");

        tokenA.mint(account, 1_000_000 ether);
        tokenB.mint(account, 1_000_000 ether);
        tokenC.mint(account, 1_000_000 ether);
        vm.deal(account, 10 ether);

        vm.startPrank(account);
        tokenA.approve(address(nonfungiblePositionManager), type(uint256).max);
        tokenB.approve(address(nonfungiblePositionManager), type(uint256).max);
        tokenC.approve(address(nonfungiblePositionManager), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenC.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // function testV3Quoter() public {
    //     vm.startPrank(account);
    //     _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);
    //     vm.stopPrank();

    //     uint256 tokenAAmount = 1e18;
    //     uint256 tokenBAmount = 1e18;

    //     // Single Pair Exact Input Quote (TokenA -> TokenB)
    //     uint256 amountOut = v3Quoter.quoteExactInputSingle(
    //         address(tokenA),
    //         address(tokenB),
    //         FEE,
    //         tokenAAmount,
    //         0
    //     );

    //     console.log("exactInput: tokenA -> tokenB quote:");
    //     console.log(amountOut);

    //     // Single Pair Exact Output Quote (TokenA -> TokenB)
    //     uint256 amountIn = v3Quoter.quoteExactOutputSingle(
    //         address(tokenA),
    //         address(tokenB),
    //         FEE,
    //         tokenBAmount,
    //         0
    //     );

    //     console.log("exactOutput: tokenA -> tokenB quote:");
    //     console.log(amountIn);

    //     assertGt(amountOut, 0);
    //     assertGt(amountIn, 0);
    // }

    // function testAddLiquidityV3() public {
    //     vm.startPrank(account);
    //     (, uint128 liquidity,,) = _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);
    //     vm.stopPrank();

    //     assertGt(uint256(liquidity), 0);
    // }

    // function testSingleSwapExactInputV3() public {
    //     vm.startPrank(account);
    //     _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);

    //     uint256 amountInTokenA = 1e18;

    //     uint256 amountOut1 = swapRouter.exactInputSingle(
    //         ISwapRouter.ExactInputSingleParams({
    //             tokenIn: address(tokenA),
    //             tokenOut: address(tokenB),
    //             fee: FEE,
    //             recipient: account,
    //             deadline: type(uint256).max,
    //             amountIn: amountInTokenA,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         })
    //     );
    //     console.log("exactInput: tokenA -> tokenB swap:");
    //     console.log(amountOut1);
    //     vm.stopPrank();

    //     assertGt(amountOut1, 0);
    // }

    // function testSingleSwapExactOutputV3() public {
    //     vm.startPrank(account);
    //     _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);

    //     uint256 amountOutTokenB = 1e18;

    //     uint256 amountIn1 = swapRouter.exactOutputSingle(
    //         ISwapRouter.ExactOutputSingleParams({
    //             tokenIn: address(tokenA),
    //             tokenOut: address(tokenB),
    //             fee: FEE,
    //             recipient: account,
    //             deadline: type(uint256).max,
    //             amountOut: amountOutTokenB,
    //             amountInMaximum: type(uint256).max,
    //             sqrtPriceLimitX96: 0
    //         })
    //     );
    //     console.log("exactOutput: tokenA -> tokenB swap:");
    //     console.log(amountIn1);
    //     vm.stopPrank();

    //     assertGt(amountIn1, 0);
    // }

    function testMultiSwapExactInputV3() public {
        vm.startPrank(account);
        _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);
        _addLiquidityV3(address(tokenB), address(tokenC), 1000e18, 2000e18);

        uint256 amountInTokenA = 1e18;

        // 构建多跳路径编码. tokenA -> tokenB -> tokenC
        bytes memory path = abi.encodePacked(
            address(tokenA),
            FEE, // 0.3%费率
            address(tokenB),
            FEE, // 0.3%费率
            address(tokenC)
        );

        uint256 amountOutC = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: account,
                deadline: type(uint256).max,
                amountIn: amountInTokenA,
                amountOutMinimum: 0
            })
        );
        console.log("exactInput: tokenA -> tokenB -> tokenC swap:");
        console.log(amountOutC);
        vm.stopPrank();

        assertGt(amountOutC, 0);
    }

    function testMultiSwapExactOutputV3() public {
        vm.startPrank(account);
        _addLiquidityV3(address(tokenA), address(tokenB), 1000e18, 2000e18);
        _addLiquidityV3(address(tokenB), address(tokenC), 1000e18, 2000e18);

        uint256 amountOutTokenC = 1e18;

        // 注意：多跳精确输出交换的路径编码与精确输入相反，需要从输出代币开始编码
        bytes memory pathReverse = abi.encodePacked(
            address(tokenC),
            FEE, // 0.3%费率
            address(tokenB),
            FEE, // 0.3%费率
            address(tokenA)
        );

        uint256 amountInA = swapRouter.exactOutput(
            ISwapRouter.ExactOutputParams({
                path: pathReverse,
                recipient: account,
                deadline: type(uint256).max,
                amountOut: amountOutTokenC,
                amountInMaximum: type(uint256).max
            })
        );
        console.log("exactOutput: tokenA -> tokenB -> tokenC swap:");
        console.log(amountInA);
        vm.stopPrank();

        assertGt(amountInA, 0);
    }

    function _addLiquidityV3(
        address tokenA_,
        address tokenB_,
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        (address token0_, address token1_) = _sortTokens(tokenA_, tokenB_);
        (uint256 token0Amount, uint256 token1Amount) =
            tokenA_ < tokenB_ ? (tokenAAmount, tokenBAmount) : (tokenBAmount, tokenAAmount);

        uint160 sqrtPriceX96 = _calculateSqrtPriceX96(token0Amount, token1Amount);
        console.log("sqrtPriceX96: ");
        console.log(uint256(sqrtPriceX96));

        nonfungiblePositionManager.createAndInitializePoolIfNecessary(
            token0_,
            token1_,
            FEE,
            sqrtPriceX96
        );

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0_,
            token1: token1_,
            fee: FEE,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: token0Amount,
            amount1Desired: token1Amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: account,
            deadline: type(uint256).max
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(mintParams);
        console.log("tokenId, liquidity, amount0, amount1: ");
        console.log(tokenId);
        console.log(uint256(liquidity));
        console.log(amount0);
        console.log(amount1);
    }

    function _sortTokens(address a, address b) internal pure returns (address, address) {
        return a < b ? (a, b) : (b, a);
    }

    function _calculateSqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        require(amount0 > 0 && amount1 > 0, "invalid amounts");
        // token1Amount * 2**192 / token0Amount
        uint256 ratioX192 = FullMath.mulDiv(amount1, uint256(1) << 192, amount0);
        return uint160(_sqrt(ratioX192));
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;
        z = y;
        uint256 x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
