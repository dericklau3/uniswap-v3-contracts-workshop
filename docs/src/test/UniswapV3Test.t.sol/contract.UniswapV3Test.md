# UniswapV3Test
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3Test.t.sol)

**Inherits:**
Test


## State Variables
### account

```solidity
address account = makeAddr("account")
```


### tokenA

```solidity
MockERC20 tokenA
```


### tokenB

```solidity
MockERC20 tokenB
```


### tokenC

```solidity
MockERC20 tokenC
```


### v3Quoter

```solidity
IQuoter v3Quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6)
```


### swapRouter

```solidity
ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564)
```


### nonfungiblePositionManager

```solidity
INonfungiblePositionManager nonfungiblePositionManager =
    INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88)
```


### token0

```solidity
address token0
```


### token1

```solidity
address token1
```


### FEE

```solidity
uint24 constant FEE = 3000
```


### TICK_LOWER

```solidity
int24 constant TICK_LOWER = -887220
```


### TICK_UPPER

```solidity
int24 constant TICK_UPPER = 887220
```


## Functions
### setUp


```solidity
function setUp() public;
```

### testAddLiquidityV3


```solidity
function testAddLiquidityV3() public;
```

### _addLiquidityV3


```solidity
function _addLiquidityV3(address tokenA_, address tokenB_, uint256 tokenAAmount, uint256 tokenBAmount)
    internal
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
```

### _sortTokens


```solidity
function _sortTokens(address a, address b) internal pure returns (address, address);
```

### _calculateSqrtPriceX96


```solidity
function _calculateSqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160);
```

### _sqrt


```solidity
function _sqrt(uint256 y) internal pure returns (uint256 z);
```

