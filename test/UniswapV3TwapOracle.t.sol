// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OracleLibrary} from "v3-periphery/contracts/libraries/OracleLibrary.sol";

import {UniswapV3TwapOracle} from "./UniswapV3TwapOracle.sol";
import {Errors} from "./lib/Errors.sol";

contract UniswapV3TwapOracleTest is Test {
    event PoolSet(address indexed token, address indexed pool);

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");
    MockMetadataToken internal quoteToken;
    MockMetadataToken internal token;
    UniswapV3TwapOracle internal oracle;

    function setUp() public {
        quoteToken = new MockMetadataToken(6);
        token = new MockMetadataToken(18);
        oracle = new UniswapV3TwapOracle(owner, address(quoteToken));
    }

    function test_ConstructorSetsConfiguration() public {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.quoteToken(), address(quoteToken));
        assertEq(oracle.TWAP_PERIOD(), 12 hours);
    }

    function test_ConstructorRevertsForZeroQuoteToken() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new UniswapV3TwapOracle(owner, address(0));
    }

    function test_ConstructorRevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new UniswapV3TwapOracle(address(0), address(quoteToken));
    }

    function test_ConstructorRevertsForUnsupportedQuoteTokenDecimals() public {
        MockMetadataToken unsupportedQuoteToken = new MockMetadataToken(19);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.UnsupportedDecimals.selector, address(unsupportedQuoteToken), uint8(19))
        );
        new UniswapV3TwapOracle(owner, address(unsupportedQuoteToken));
    }

    function test_SetPoolStoresPoolAndEmitsEvent() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));

        vm.expectEmit(true, true, false, true);
        emit PoolSet(address(token), address(pool));

        vm.prank(owner);
        oracle.setPool(address(token), address(pool));

        assertEq(oracle.pools(address(token)), address(pool));
    }

    function test_SetPoolReplacesExistingPool() public {
        MockObservablePool firstPool = new MockObservablePool(address(token), address(quoteToken));
        MockObservablePool secondPool = new MockObservablePool(address(quoteToken), address(token));

        vm.startPrank(owner);
        oracle.setPool(address(token), address(firstPool));
        oracle.setPool(address(token), address(secondPool));
        vm.stopPrank();

        assertEq(oracle.pools(address(token)), address(secondPool));
    }

    function test_SetPoolRevertsForNonOwner() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        oracle.setPool(address(token), address(pool));
    }

    function test_SetPoolRevertsForZeroToken() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        oracle.setPool(address(0), address(pool));
    }

    function test_SetPoolRevertsForZeroPool() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(owner);
        oracle.setPool(address(token), address(0));
    }

    function test_SetPoolRevertsWhenTokenIsQuoteToken() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));

        vm.expectRevert(Errors.InvalidToken.selector);
        vm.prank(owner);
        oracle.setPool(address(quoteToken), address(pool));
    }

    function test_SetPoolRevertsForNonContractPool() public {
        vm.expectRevert(Errors.InvalidPool.selector);
        vm.prank(owner);
        oracle.setPool(address(token), makeAddr("not-a-contract"));
    }

    function test_SetPoolRevertsForMismatchedPair() public {
        MockMetadataToken otherToken = new MockMetadataToken(18);
        MockObservablePool pool = new MockObservablePool(address(token), address(otherToken));

        vm.expectRevert(Errors.InvalidPool.selector);
        vm.prank(owner);
        oracle.setPool(address(token), address(pool));
    }

    function test_SetPoolRevertsForUnsupportedTokenDecimals() public {
        MockMetadataToken unsupportedToken = new MockMetadataToken(19);
        MockObservablePool pool = new MockObservablePool(address(unsupportedToken), address(quoteToken));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.UnsupportedDecimals.selector, address(unsupportedToken), uint8(19))
        );
        vm.prank(owner);
        oracle.setPool(address(unsupportedToken), address(pool));
    }

    function test_GetPriceUsesTwelveHourTwapAndNormalizesEighteenBySixDecimals() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));

        vm.prank(owner);
        oracle.setPool(address(token), address(pool));

        assertEq(oracle.getPrice(address(token)), 1e30);
    }

    function test_GetPriceNormalizesEightBySixDecimals() public {
        MockMetadataToken eightDecimalToken = new MockMetadataToken(8);
        MockObservablePool pool = new MockObservablePool(address(eightDecimalToken), address(quoteToken));

        vm.prank(owner);
        oracle.setPool(address(eightDecimalToken), address(pool));

        assertEq(oracle.getPrice(address(eightDecimalToken)), 1e20);
    }

    function test_GetPriceSupportsReversePoolTokenOrdering() public {
        MockObservablePool pool = new MockObservablePool(address(quoteToken), address(token));
        pool.setArithmeticMeanTick(100);

        vm.prank(owner);
        oracle.setPool(address(token), address(pool));

        uint256 rawQuote = OracleLibrary.getQuoteAtTick(100, 1e18, address(token), address(quoteToken));
        assertEq(oracle.getPrice(address(token)), rawQuote * 1e12);
    }

    function test_GetPriceRevertsWhenPoolIsNotConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.PoolNotConfigured.selector, address(token)));
        oracle.getPrice(address(token));
    }

    function test_GetPricePropagatesInsufficientHistoryFailure() public {
        MockObservablePool pool = new MockObservablePool(address(token), address(quoteToken));
        pool.setInsufficientHistory(true);

        vm.prank(owner);
        oracle.setPool(address(token), address(pool));

        vm.expectRevert(MockObservablePool.InsufficientHistory.selector);
        oracle.getPrice(address(token));
    }
}

contract MockMetadataToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract MockObservablePool {
    error InvalidPeriod();
    error InsufficientHistory();

    address public immutable token0;
    address public immutable token1;
    bool public insufficientHistory;
    int24 public arithmeticMeanTick;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function setInsufficientHistory(bool insufficientHistory_) external {
        insufficientHistory = insufficientHistory_;
    }

    function setArithmeticMeanTick(int24 arithmeticMeanTick_) external {
        arithmeticMeanTick = arithmeticMeanTick_;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        if (insufficientHistory) revert InsufficientHistory();
        if (secondsAgos.length != 2 || secondsAgos[0] != 12 hours || secondsAgos[1] != 0) {
            revert InvalidPeriod();
        }

        tickCumulatives = new int56[](2);
        tickCumulatives[1] = int56(arithmeticMeanTick) * int56(uint56(secondsAgos[0]));

        secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[1] = uint160(secondsAgos[0]);
    }
}
