// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "v3-periphery/contracts/libraries/OracleLibrary.sol";

import {Errors} from "./lib/Errors.sol";

/// @title Uniswap V3 12 小时时间加权平均价格预言机
/// @notice 使用同一个不可变基础币为已配置的代币计价，并将所有价格统一为 18 位精度。
contract UniswapV3TwapOracle is Ownable2Step {
    /// @notice owner 设置或替换代币计价池时触发。
    /// @param token 需要查询价格的代币。
    /// @param pool 同时包含 `token` 和 `quoteToken` 的 Uniswap V3 池。
    event PoolSet(address indexed token, address indexed pool);

    /// @notice 固定的 TWAP 观察窗口，单位为秒。
    uint32 public constant TWAP_PERIOD = 12 hours;

    /// @notice 当前部署中所有价格统一使用的基础币。
    address public immutable quoteToken;
    uint8 internal immutable quoteTokenDecimals;

    /// @notice 返回指定代币已配置的 Uniswap V3 池。
    mapping(address token => address pool) public pools;
    mapping(address token => uint8 decimals) internal tokenDecimals;

    /// @notice 使用指定 owner 和当前链的基础币创建预言机。
    /// @param initialOwner 有权配置代币池的账户。
    /// @param quoteToken_ 所有已配置池统一使用的 USDC、USDT 或其他基础币。
    constructor(address initialOwner, address quoteToken_) Ownable(initialOwner) {
        require(quoteToken_ != address(0), Errors.ZeroAddress());

        uint8 decimals = IERC20Metadata(quoteToken_).decimals();
        require(decimals <= 18, Errors.UnsupportedDecimals(quoteToken_, decimals));

        quoteToken = quoteToken_;
        quoteTokenDecimals = decimals;
    }

    /// @notice 设置或替换用于计算 `token` 价格的 Uniswap V3 池。
    /// @dev 该池必须只包含 `token` 和不可变的 `quoteToken`，且仅 owner 可以调用。
    /// @param token 需要计价的代币。
    /// @param pool 作为 12 小时价格观察来源的 Uniswap V3 池。
    function setPool(address token, address pool) external onlyOwner {
        require(token != address(0) && pool != address(0), Errors.ZeroAddress());
        require(token != quoteToken, Errors.InvalidToken());
        require(pool.code.length != 0, Errors.InvalidPool());

        address poolToken0 = IUniswapV3Pool(pool).token0();
        address poolToken1 = IUniswapV3Pool(pool).token1();

        bool validPair =
            (poolToken0 == token && poolToken1 == quoteToken) || (poolToken0 == quoteToken && poolToken1 == token);
        require(validPair, Errors.InvalidPool());

        uint8 decimals = IERC20Metadata(token).decimals();
        require(decimals <= 18, Errors.UnsupportedDecimals(token, decimals));

        pools[token] = pool;
        tokenDecimals[token] = decimals;

        emit PoolSet(token, pool);
    }

    /// @notice 返回一个完整 `token` 的 12 小时 TWAP，并以基础币计价。
    /// @dev 返回值始终为 18 位精度；Uniswap 观察数据不足等错误会原样向上传递。
    /// @param token 已配置池并需要查询价格的代币。
    /// @return price 一个完整代币对应的基础币价值，统一为 18 位精度。
    function getPrice(address token) external view returns (uint256 price) {
        address pool = pools[token];
        require(pool != address(0), Errors.PoolNotConfigured(token));

        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, TWAP_PERIOD);
        uint128 baseAmount = uint128(10 ** uint256(tokenDecimals[token]));
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, baseAmount, token, quoteToken);

        price = quoteAmount * (10 ** uint256(18 - quoteTokenDecimals));
    }
}
