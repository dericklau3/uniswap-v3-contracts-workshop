# Uniswap V3 Flash Loan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone single-token Uniswap V3 flash-loan template with callback validation, repayment, and immutable profit distribution.

**Architecture:** `UniswapV3FlashLoan` stores a transient request context before calling a supplied V3 pool. Its callback validates that context, invokes a direct-edit internal customization function, repays the borrowed token plus the pool-reported fee, then sends the remaining borrowed-token balance to the immutable recipient.

**Tech Stack:** Solidity 0.8.30, Foundry, Uniswap V3 core interfaces, OpenZeppelin `SafeERC20`

---

### Task 1: Define Flash-Loan Errors

**Files:**
- Modify: `test/lib/Errors.sol`

- [ ] Add errors for invalid amount, invalid parameters, active loans, unexpected callbacks, and insufficient repayment balance.
- [ ] Run `forge test --match-path test/UniswapV3TwapOracle.t.sol` and expect the existing oracle tests to pass.

### Task 2: Write Failing Flash-Loan Tests

**Files:**
- Create: `test/UniswapV3FlashLoan.t.sol`
- Test: `test/UniswapV3FlashLoan.t.sol`

- [ ] Add a mock ERC-20 and mock V3 flash pool.
- [ ] Test constructor validation and immutable recipient storage.
- [ ] Test token0 and token1 borrowing, exact principal-plus-fee repayment, and profit transfer.
- [ ] Test zero addresses, zero amount, non-pool token, nested calls, forged callbacks, and insufficient repayment balance.
- [ ] Run `forge test --match-path test/UniswapV3FlashLoan.t.sol` and expect compilation to fail because `UniswapV3FlashLoan.sol` does not exist.

### Task 3: Implement the Standalone Contract

**Files:**
- Create: `test/UniswapV3FlashLoan.sol`
- Test: `test/UniswapV3FlashLoan.t.sol`

- [ ] Implement `IUniswapV3FlashCallback` with `SafeERC20`.
- [ ] Store the immutable `PROFIT_RECIPIENT` and transient pool, token, amount, and initiator context.
- [ ] Implement `startFlashLoan` validation and the one-sided `pool.flash` call.
- [ ] Validate callback sender and encoded request, select the correct V3 fee, and invoke `_executeFlashLoan`.
- [ ] Repay principal plus fee, transfer remaining borrowed token to the profit recipient, and leave `_executeFlashLoan` non-virtual with an empty body.
- [ ] Run `forge test --match-path test/UniswapV3FlashLoan.t.sol` and expect all flash-loan tests to pass.

### Task 4: Verify the Repository

**Files:**
- Verify: `test/UniswapV3FlashLoan.sol`
- Verify: `test/UniswapV3FlashLoan.t.sol`
- Verify: `test/lib/Errors.sol`

- [ ] Run `forge fmt --check`.
- [ ] Run `forge test --match-path test/UniswapV3FlashLoan.t.sol`.
- [ ] Run `forge test` and report any unrelated environment or pre-existing failures separately.
- [ ] Run `git diff --check` and `git status --short` to confirm the final scope.
