# Uniswap V3 TWAP Oracle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an owner-managed 12-hour Uniswap V3 TWAP oracle whose token prices are denominated in one immutable quote token and normalized to 18 decimals.

**Architecture:** A focused `UniswapV3TwapOracle` contract stores one validated pool per priced token. It delegates TWAP tick calculation and quote conversion to Uniswap V3's `OracleLibrary`, while OpenZeppelin `Ownable2Step` protects configuration. Unit tests use mock metadata tokens and an observable mock pool to verify access, validation, timing, ordering, decimal normalization, and oracle failure propagation without RPC access.

**Tech Stack:** Solidity 0.8.30, Foundry, forge-std, OpenZeppelin Contracts 5.x, Uniswap V3 core/periphery libraries.

---

### Task 1: Establish the contract API with failing constructor tests

**Files:**
- Create: `test/UniswapV3TwapOracle.t.sol`
- Create: `test/UniswapV3TwapOracle.sol`

- [ ] **Step 1: Write the failing constructor test**

Create mock ERC20 metadata tokens and assert that construction records the owner, quote token, and fixed `TWAP_PERIOD` of 12 hours.

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `forge test --match-contract UniswapV3TwapOracleTest --match-test test_Constructor -vv`

Expected: compilation fails because `UniswapV3TwapOracle.sol` does not exist or the contract API is not implemented.

- [ ] **Step 3: Implement the minimal constructor and immutable state**

Create `UniswapV3TwapOracle` with `Ownable2Step`, immutable `quoteToken`, constant `TWAP_PERIOD`, zero-address checks, and cached quote-token decimals validation.

- [ ] **Step 4: Run constructor tests**

Run: `forge test --match-contract UniswapV3TwapOracleTest --match-test test_Constructor -vv`

Expected: all constructor tests pass.

### Task 2: Add owner-only validated pool configuration

**Files:**
- Modify: `test/UniswapV3TwapOracle.t.sol`
- Modify: `test/UniswapV3TwapOracle.sol`

- [ ] **Step 1: Write failing configuration tests**

Cover owner-only access, zero addresses, quote token rejection, non-contract pools, pair mismatch, unsupported token decimals, event emission, storage, and replacement.

- [ ] **Step 2: Run configuration tests to verify failure**

Run: `forge test --match-contract UniswapV3TwapOracleTest --match-test test_SetPool -vv`

Expected: tests fail because `setPool` and pool validation are missing.

- [ ] **Step 3: Implement minimal pool configuration**

Add `pools`, `PoolSet`, local custom errors, and `setPool`. Read `token0` and `token1` through `IUniswapV3Pool`, require an exact token/quote-token pair in either order, and cache each priced token's decimals.

- [ ] **Step 4: Run configuration tests**

Run: `forge test --match-contract UniswapV3TwapOracleTest --match-test test_SetPool -vv`

Expected: all pool configuration tests pass.

### Task 3: Add 12-hour TWAP price calculation and decimal normalization

**Files:**
- Modify: `test/UniswapV3TwapOracle.t.sol`
- Modify: `test/UniswapV3TwapOracle.sol`

- [ ] **Step 1: Write failing price tests**

Configure observable mock pools with cumulative ticks corresponding to known arithmetic mean ticks. Cover a 12-hour request, both pool token orderings, 18/6 and 8/6 decimal combinations, missing configuration, and observation failure propagation.

- [ ] **Step 2: Run price tests to verify failure**

Run: `forge test --match-contract UniswapV3TwapOracleTest --match-test test_GetPrice -vv`

Expected: tests fail because `getPrice` is missing.

- [ ] **Step 3: Implement minimal price calculation**

Call `OracleLibrary.consult(pool, TWAP_PERIOD)`, quote one whole priced token with `OracleLibrary.getQuoteAtTick`, and scale the raw quote amount to 18 decimals.

- [ ] **Step 4: Run all focused oracle tests**

Run: `forge test --match-contract UniswapV3TwapOracleTest -vv`

Expected: all oracle tests pass.

### Task 4: Document and verify the complete change

**Files:**
- Create: `test/docs/UniswapV3TwapOracleTest.md`
- Review: `test/UniswapV3TwapOracle.sol`
- Review: `test/UniswapV3TwapOracle.t.sol`

- [ ] **Step 1: Write focused test documentation**

Document the test setup, owner configuration scenarios, mock observation behavior, 12-hour assumption, token ordering, decimal normalization, and expected Uniswap failure propagation.

- [ ] **Step 2: Format the new Solidity files**

Run: `forge fmt test/UniswapV3TwapOracle.sol test/UniswapV3TwapOracle.t.sol`

Expected: command exits successfully.

- [ ] **Step 3: Run the focused test suite**

Run: `forge test --match-contract UniswapV3TwapOracleTest -vv`

Expected: all focused tests pass.

- [ ] **Step 4: Run the full test suite**

Run: `forge test`

Expected: all tests pass, or any unrelated pre-existing RPC/environment blocker is reported exactly.

- [ ] **Step 5: Inspect the final diff**

Run: `git diff --check`

Expected: no whitespace errors.

Run: `git status --short`

Expected: only the newly added oracle, tests, docs, and pre-existing user changes appear.
