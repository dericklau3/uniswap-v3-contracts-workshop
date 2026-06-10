# Errors
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/lib/Errors.sol)

**Title:**
Workshop 错误定义

集中定义测试目录示例合约使用的自定义错误。


## Errors
### ZeroAddress

```solidity
error ZeroAddress();
```

### InvalidToken

```solidity
error InvalidToken();
```

### InvalidPool

```solidity
error InvalidPool();
```

### InvalidParameter

```solidity
error InvalidParameter();
```

### InvalidFlashLoanAmount

```solidity
error InvalidFlashLoanAmount();
```

### FlashLoanInProgress

```solidity
error FlashLoanInProgress();
```

### UnexpectedCallback

```solidity
error UnexpectedCallback();
```

### InsufficientRepaymentBalance

```solidity
error InsufficientRepaymentBalance();
```

### PoolNotConfigured

```solidity
error PoolNotConfigured(address token);
```

### UnsupportedDecimals

```solidity
error UnsupportedDecimals(address token, uint8 decimals);
```

