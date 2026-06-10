# Uniswap V3 TWAP Oracle Design

## Goal

Add an owner-managed Uniswap V3 TWAP oracle under `test/`. The oracle prices
configured tokens in one deployment-wide quote token, such as USDC or USDT,
using a fixed 12-hour window. Every value returned by `getPrice` uses 18
decimals.

## Contract API

The contract is named `UniswapV3TwapOracle`.

```solidity
constructor(address initialOwner, address quoteToken)

function setPool(address token, address pool) external onlyOwner

function getPrice(address token) external view returns (uint256 price)

function pools(address token) external view returns (address pool)

function quoteToken() external view returns (address)
```

`initialOwner` and `quoteToken` must be nonzero addresses. The quote token is
immutable so each chain deployment has one consistent base unit.

## Ownership

The oracle uses OpenZeppelin `Ownable2Step`. Every configuration operation is
restricted to the owner. In the initial scope, `setPool` is the only oracle
configuration operation.

## Pool Configuration

`setPool(token, pool)` stores the Uniswap V3 pool used to price `token`.

The call reverts when:

- `token` or `pool` is the zero address.
- `token` equals the deployment-wide quote token.
- `pool` is not a contract.
- The pool's `token0` and `token1` are not exactly `token` and `quoteToken` in
  either order.
- Either token reports more than 18 decimals.

Successful configuration emits:

```solidity
event PoolSet(address indexed token, address indexed pool);
```

Calling `setPool` again replaces the existing pool for that token.

## Price Calculation

`getPrice(token)` returns the quote-token value of one whole `token`, normalized
to 18 decimals.

The calculation is:

1. Load the configured pool or revert if none exists.
2. Use `OracleLibrary.consult(pool, 12 hours)` to obtain the arithmetic mean
   tick over the preceding 43,200 seconds.
3. Use `10 ** tokenDecimals` as the base amount so the quote represents one
   whole token.
4. Pass the mean tick, base amount, token address, and quote-token address to
   `OracleLibrary.getQuoteAtTick`.
5. Scale the raw quote-token amount from `quoteToken.decimals()` to 18 decimals.

The Uniswap library handles token ordering, so the result has the same meaning
whether the configured token is `token0` or `token1`.

The call reverts when the pool does not contain enough initialized observation
history for a 12-hour consultation. This preserves the underlying Uniswap V3
oracle safety behavior instead of falling back to a shorter or spot price.

## Errors

The contract uses custom errors for local validation:

```solidity
error ZeroAddress();
error InvalidToken();
error InvalidPool();
error PoolNotConfigured(address token);
error UnsupportedDecimals(address token, uint8 decimals);
```

Errors raised by the Uniswap V3 pool or `OracleLibrary` are propagated.

## Tests

The Foundry tests use small mock metadata tokens and a mock observable pool so
they do not require RPC access.

Tests cover:

- Constructor state and zero-address validation.
- Owner-only pool configuration.
- Validation that the pool contains exactly the token and quote token.
- Pool replacement and `PoolSet` emission.
- A 12-hour consultation request.
- Correct pricing for both pool token orderings.
- Token and quote-token decimal combinations including 18/6 and 8/6.
- An 18-decimal `getPrice` result.
- Missing pool and unsupported decimal reverts.
- Propagation of insufficient observation-history failures.

## Files

- `test/UniswapV3TwapOracle.sol`: oracle implementation.
- `test/UniswapV3TwapOracle.t.sol`: focused unit tests and mocks.
- `test/docs/UniswapV3TwapOracleTest.md`: test assumptions and scenario
  documentation.
