# MockUniswapV3FlashPool
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3FlashLoan.t.sol)


## State Variables
### token0

```solidity
address public immutable token0
```


### token1

```solidity
address public immutable token1
```


### flashFee

```solidity
uint256 public immutable flashFee
```


### lastAmount0

```solidity
uint256 public lastAmount0
```


### lastAmount1

```solidity
uint256 public lastAmount1
```


### reenter

```solidity
bool public reenter
```


### corruptCallbackData

```solidity
bool public corruptCallbackData
```


## Functions
### constructor


```solidity
constructor(address token0_, address token1_, uint256 flashFee_) ;
```

### setReenter


```solidity
function setReenter(bool reenter_) external;
```

### setCorruptCallbackData


```solidity
function setCorruptCallbackData(bool corruptCallbackData_) external;
```

### flash


```solidity
function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
```

