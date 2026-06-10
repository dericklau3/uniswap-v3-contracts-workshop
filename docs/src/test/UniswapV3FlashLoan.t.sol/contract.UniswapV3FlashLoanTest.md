# UniswapV3FlashLoanTest
[Git Source](https://github.com/dericklau3/uniswap-v3-contracts-workshop/blob/ea1e6b95fd3bd1697200950ba44ef189dc8acf20/test/UniswapV3FlashLoan.t.sol)

**Inherits:**
Test


## State Variables
### BORROW_AMOUNT

```solidity
uint256 internal constant BORROW_AMOUNT = 100 ether
```


### FLASH_FEE

```solidity
uint256 internal constant FLASH_FEE = 0.3 ether
```


### PROFIT

```solidity
uint256 internal constant PROFIT = 5 ether
```


### profitRecipient

```solidity
address internal profitRecipient = makeAddr("profitRecipient")
```


### token0

```solidity
MockFlashToken internal token0
```


### token1

```solidity
MockFlashToken internal token1
```


### pool

```solidity
MockUniswapV3FlashPool internal pool
```


### flashLoan

```solidity
UniswapV3FlashLoan internal flashLoan
```


## Functions
### setUp


```solidity
function setUp() public;
```

### test_ConstructorSetsProfitRecipient


```solidity
function test_ConstructorSetsProfitRecipient() public view;
```

### test_ConstructorRevertsForZeroProfitRecipient


```solidity
function test_ConstructorRevertsForZeroProfitRecipient() public;
```

### test_StartFlashLoanBorrowsToken0RepaysFeeAndTransfersProfit


```solidity
function test_StartFlashLoanBorrowsToken0RepaysFeeAndTransfersProfit() public;
```

### test_StartFlashLoanBorrowsToken1RepaysFeeAndTransfersProfit


```solidity
function test_StartFlashLoanBorrowsToken1RepaysFeeAndTransfersProfit() public;
```

### test_StartFlashLoanRevertsForZeroPool


```solidity
function test_StartFlashLoanRevertsForZeroPool() public;
```

### test_StartFlashLoanRevertsForZeroToken


```solidity
function test_StartFlashLoanRevertsForZeroToken() public;
```

### test_StartFlashLoanRevertsForZeroAmount


```solidity
function test_StartFlashLoanRevertsForZeroAmount() public;
```

### test_StartFlashLoanRevertsForTokenOutsidePool


```solidity
function test_StartFlashLoanRevertsForTokenOutsidePool() public;
```

### test_StartFlashLoanRevertsWhenLoanIsAlreadyInProgress


```solidity
function test_StartFlashLoanRevertsWhenLoanIsAlreadyInProgress() public;
```

### test_FlashCallbackRevertsWhenCalledWithoutActiveLoan


```solidity
function test_FlashCallbackRevertsWhenCalledWithoutActiveLoan() public;
```

### test_FlashCallbackRevertsWhenPoolChangesCallbackData


```solidity
function test_FlashCallbackRevertsWhenPoolChangesCallbackData() public;
```

### test_FlashCallbackRevertsForInsufficientRepaymentBalance


```solidity
function test_FlashCallbackRevertsForInsufficientRepaymentBalance() public;
```

