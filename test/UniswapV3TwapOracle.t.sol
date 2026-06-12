// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {UniswapV3TwapOracle} from "./UniswapV3TwapOracle.sol";
import {Errors} from "./lib/Errors.sol";

contract UniswapV3TwapOracleTest is Test {
    event PoolSet(address indexed token, address indexed pool);

    uint256 internal constant MAINNET_FORK_BLOCK = 25298585;
    uint24 internal constant FEE = 3000;

    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    IUniswapV3Factory internal factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
    address internal wethUsdtPool;
    address internal wbtcUsdtPool;

    function setUp() public {
        vm.createSelectFork("mainnet", MAINNET_FORK_BLOCK);

        wethUsdtPool = factory.getPool(WETH, USDT, FEE);
        wbtcUsdtPool = factory.getPool(WBTC, USDT, FEE);

        assertNotEq(wethUsdtPool, address(0));
        assertNotEq(wbtcUsdtPool, address(0));
    }

    function test_ConstructorSetsRealMainnetConfiguration() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        assertEq(oracle.owner(), owner);
        assertEq(oracle.quoteToken(), USDT);
        assertEq(oracle.TWAP_PERIOD(), 1 hours);
        assertEq(oracle.minimumObservationCardinality(), 150);
    }

    function test_ConstructorRevertsForZeroQuoteToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new UniswapV3TwapOracle(owner, address(0), 150);
    }

    function test_ConstructorRevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new UniswapV3TwapOracle(address(0), USDT, 150);
    }

    function test_SetWethUsdtPoolExpandsObservationCapacity() public {
        uint16 observationCardinalityNextBefore = _observationCardinalityNext(wethUsdtPool);
        uint16 targetObservationCardinality = observationCardinalityNextBefore + 1;
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, targetObservationCardinality);

        vm.expectEmit(true, true, false, true);
        emit PoolSet(WETH, wethUsdtPool);

        vm.prank(owner);
        oracle.setPool(WETH, wethUsdtPool);

        assertEq(oracle.pools(WETH), wethUsdtPool);
        assertEq(_observationCardinalityNext(wethUsdtPool), targetObservationCardinality);
    }

    function test_SetWbtcUsdtPoolSkipsExpansionWhenCapacityAlreadyMet() public {
        uint16 observationCardinalityNextBefore = _observationCardinalityNext(wbtcUsdtPool);
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, observationCardinalityNextBefore);

        vm.prank(owner);
        oracle.setPool(WBTC, wbtcUsdtPool);

        assertEq(oracle.pools(WBTC), wbtcUsdtPool);
        assertEq(_observationCardinalityNext(wbtcUsdtPool), observationCardinalityNextBefore);
    }

    function test_SetPoolRevertsForNonOwner() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        oracle.setPool(WETH, wethUsdtPool);
    }

    function test_SetPoolRevertsForZeroToken() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        oracle.setPool(address(0), wethUsdtPool);
    }

    function test_SetPoolRevertsForZeroPool() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        oracle.setPool(WETH, address(0));
    }

    function test_SetPoolRevertsWhenTokenIsQuoteToken() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(Errors.InvalidToken.selector);
        vm.prank(owner);
        oracle.setPool(USDT, wethUsdtPool);
    }

    function test_SetPoolRevertsForNonContractPool() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(Errors.InvalidPool.selector);
        vm.prank(owner);
        oracle.setPool(WETH, makeAddr("not-a-contract"));
    }

    function test_SetPoolRevertsForMismatchedRealPool() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(Errors.InvalidPool.selector);
        vm.prank(owner);
        oracle.setPool(WETH, wbtcUsdtPool);
    }

    function test_GetWethPriceReturnsOneHourTwapNormalizedToEighteenDecimals() public {
        UniswapV3TwapOracle oracle = _configureOracle(WETH, wethUsdtPool);

        uint256 price = oracle.getPrice(WETH);
        console.log("WETH price in USDT with 18 decimals:", price);

        assertGt(price, 100e18);
        assertLt(price, 100_000e18);
    }

    function test_GetWbtcPriceReturnsOneHourTwapNormalizedToEighteenDecimals() public {
        UniswapV3TwapOracle oracle = _configureOracle(WBTC, wbtcUsdtPool);

        uint256 price = oracle.getPrice(WBTC);
        console.log("WBTC price in USDT with 18 decimals:", price);
        assertGt(price, 1_000e18);
        assertLt(price, 1_000_000e18);
    }

    function test_GetPriceRevertsWhenPoolIsNotConfigured() public {
        UniswapV3TwapOracle oracle = new UniswapV3TwapOracle(owner, USDT, 150);

        vm.expectRevert(abi.encodeWithSelector(Errors.PoolNotConfigured.selector, WETH));
        oracle.getPrice(WETH);
    }

    function _configureOracle(address token, address pool) internal returns (UniswapV3TwapOracle oracle) {
        oracle = new UniswapV3TwapOracle(owner, USDT, _observationCardinalityNext(pool));

        vm.prank(owner);
        oracle.setPool(token, pool);
    }

    function _observationCardinalityNext(address pool) internal view returns (uint16 observationCardinalityNext) {
        assertGt(pool.code.length, 0);
        assertEq(IUniswapV3Pool(pool).factory(), UNISWAP_V3_FACTORY);
        assertEq(IUniswapV3Pool(pool).fee(), FEE);

        (,,,, observationCardinalityNext,,) = IUniswapV3Pool(pool).slot0();
    }
}
