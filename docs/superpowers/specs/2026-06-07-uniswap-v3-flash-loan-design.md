# Uniswap V3 Flash Loan Design

## Goal

Add a standalone `UniswapV3FlashLoan` contract under `test/` that borrows one
token from a caller-supplied Uniswap V3 pool, runs an internal customization
point, repays principal plus the pool-provided fee, and transfers the remaining
borrowed token to an immutable profit recipient.

## Contract API

- Constructor: `constructor(address profitRecipient_)`
- Entry point:
  `startFlashLoan(address pool, address borrowToken, uint256 borrowAmount)`
- Callback:
  `uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data)`
- Immutable recipient: `address public immutable PROFIT_RECIPIENT`

The entry point accepts only one of the pool's two tokens and maps the requested
amount to either `amount0` or `amount1` when calling `pool.flash`.

## Callback Safety

The contract stores the active pool and initiator before calling `flash`.
The callback must come from that active pool and its encoded token and amount
must match the active request. A second flash loan cannot start while one is in
progress.

The callback selects the applicable fee from `fee0` or `fee1`, calls the
non-virtual internal `_executeFlashLoan` customization point, verifies that the
contract holds at least principal plus fee, and repays the pool with
`SafeERC20`.

## Profit Handling

After repayment, the contract transfers its entire remaining balance of the
borrowed token to `PROFIT_RECIPIENT`. Other tokens are not swept.

## Custom Logic

`_executeFlashLoan` is an internal, non-virtual function with the pool, token,
amount, fee, and initiator as parameters. Its default body is empty so workshop
users can edit the function directly to add arbitrage, liquidation, or other
atomic logic without inheritance.

## Testing

Use a mock V3 pool that transfers the requested token, invokes the callback,
and verifies repayment. Cover constructor validation, token0 and token1 loans,
fee repayment, profit transfer, invalid parameters, nested loans, forged
callbacks, and insufficient repayment balance.
