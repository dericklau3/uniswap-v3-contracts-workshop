# UniswapV3TwapOracle Tests

## Purpose

`test/UniswapV3TwapOracle.t.sol` verifies the owner-managed configuration and
price normalization behavior of `UniswapV3TwapOracle` without requiring a fork
or RPC endpoint.

## Setup

Each test deploys:

- A 6-decimal mock quote token representing USDC or USDT.
- An 18-decimal mock priced token.
- An oracle whose configuration owner is a dedicated test address.
- Mock observable pools as needed by each scenario.

The metadata token mocks expose only `decimals()`, which is the ERC20 metadata
surface used by the oracle.

## Configuration Scenarios

The tests verify:

- Constructor storage, zero addresses, and the 18-decimal maximum.
- Only the owner can call `setPool`.
- A pool must be a contract containing exactly the priced token and quote token.
- The quote token cannot be configured as a priced token.
- Pool assignment emits `PoolSet` and a later owner call can replace it.

## TWAP Scenarios

The observable pool mock accepts only `[43_200, 0]` as its `observe` request.
Any other period reverts, so successful price tests prove that the oracle uses
the fixed 12-hour window.

The mock returns cumulative values for a configurable arithmetic mean tick.
It can also simulate insufficient history, whose error must propagate through
`getPrice`.

## Decimal Assumptions

At tick zero, one base-token smallest unit equals one quote-token smallest
unit. This intentionally produces:

- `1e30` for an 18-decimal token quoted by a 6-decimal token.
- `1e20` for an 8-decimal token quoted by a 6-decimal token.

These values verify that the oracle prices one whole input token and then
normalizes the resulting quote-token amount to 18 decimals. A nonzero-tick test
also verifies token-address quote direction when the quote token is pool
`token0`.
