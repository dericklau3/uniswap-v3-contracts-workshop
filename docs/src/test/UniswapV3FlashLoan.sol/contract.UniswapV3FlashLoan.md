# UniswapV3FlashLoan
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3FlashLoan.sol)

**Inherits:**
IUniswapV3FlashCallback

**Title:**
Uniswap V3 Flash Loan 模板

从指定 V3 pool 借出单个 token，执行自定义逻辑，归还本息并转出剩余盈利。


## State Variables
### PROFIT_RECIPIENT
flash loan 结束后接收借入 token 剩余余额的地址。


```solidity
address public immutable PROFIT_RECIPIENT
```


### context

```solidity
FlashLoanContext private context
```


## Functions
### constructor


```solidity
constructor(address profitRecipient_) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`profitRecipient_`|`address`|flash loan 盈利接收地址。|


### startFlashLoan

从指定 Uniswap V3 pool 借出单个 token。

`borrowToken` 必须是 pool 的 token0 或 token1，且同一时间只能执行一笔 flash loan。


```solidity
function startFlashLoan(address pool, address borrowToken, uint256 borrowAmount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pool`|`address`|提供 flash loan 的 Uniswap V3 pool。|
|`borrowToken`|`address`|要借出的 token。|
|`borrowAmount`|`uint256`|要借出的数量。|


### uniswapV3FlashCallback

V3 pool 发放借款后调用的回调。

只接受由当前 `startFlashLoan` 指定 pool 发起且参数完全匹配的回调。


```solidity
function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override;
```

### _executeFlashLoan

在这里直接填写套利、清算或其他需要使用 flash loan 资金的原子逻辑。


```solidity
function _executeFlashLoan(address pool, address borrowToken, uint256 borrowAmount, uint256 fee, address initiator)
    internal;
```

## Structs
### FlashLoanContext

```solidity
struct FlashLoanContext {
    address pool;
    address initiator;
    address borrowToken;
    uint256 borrowAmount;
}
```

