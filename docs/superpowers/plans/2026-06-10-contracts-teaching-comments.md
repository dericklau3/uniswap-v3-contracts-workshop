# Contracts Teaching Comments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Chinese comments in production contracts as layered, business-oriented teaching notes without changing Solidity behavior.

**Architecture:** Work by conceptual subsystem so each pass tells one coherent Uniswap story. Preserve code tokens exactly, review diffs for comment-only changes, then compile the complete repository.

**Tech Stack:** Solidity 0.7.x, Foundry, Uniswap V2/V3 core and periphery contracts.

---

### Task 1: V3 Core Pool Lifecycle

**Files:**
- Modify: `contracts/v3-core/NoDelegateCall.sol`
- Modify: `contracts/v3-core/UniswapV3Factory.sol`
- Modify: `contracts/v3-core/UniswapV3Pool.sol`
- Modify: `contracts/v3-core/UniswapV3PoolDeployer.sol`

- [x] Explain deployment parameters, pool initialization, LP position changes, swap loop, callbacks, flash loans, fee collection, and protocol administration.
- [x] Add business examples around token payment direction and active liquidity.
- [x] Inspect the diff and confirm only comments changed.

### Task 2: V3 Core Accounting And Oracle

**Files:**
- Modify: `contracts/v3-core/libraries/Oracle.sol`
- Modify: `contracts/v3-core/libraries/Position.sol`
- Modify: `contracts/v3-core/libraries/Tick.sol`
- Modify: `contracts/v3-core/libraries/TickBitmap.sol`

- [x] Preserve the existing `Oracle.sol` work and normalize its teaching style.
- [x] Explain LP fee snapshots, inside/outside accounting, tick crossing, bitmap lookup, and observation interpolation.
- [x] Inspect the diff and confirm only comments changed.

### Task 3: V3 Core Mathematics And Token Utilities

**Files:**
- Modify: production library files under `contracts/v3-core/libraries/` not covered by Task 2.

- [x] Explain fixed-point units, rounding direction, overflow assumptions, price/liquidity deltas, and swap-step outputs.
- [x] Use short numerical or business examples only where they clarify a non-obvious formula.
- [x] Inspect the diff and confirm only comments changed.

### Task 4: V3 Periphery Position And Payment Flows

**Files:**
- Modify: production contracts under `contracts/v3-periphery/`, excluding `interfaces/`, `test/`, router and lens files covered later.

- [x] Explain NFT position ownership versus core positions, mint/increase/decrease/collect flows, callbacks, ETH/WETH handling, permits, migration, and flash-arbitrage examples.
- [x] Make payer, recipient, pool, and refund responsibilities explicit.
- [x] Inspect the diff and confirm only comments changed.

### Task 5: V3 Periphery Routing, Quoting, And Libraries

**Files:**
- Modify: `contracts/v3-periphery/SwapRouter.sol`
- Modify: production files under `contracts/v3-periphery/lens/`
- Modify: production files under `contracts/v3-periphery/libraries/`

- [x] Explain exact-input forward execution, exact-output reverse execution, path encoding, callback validation, quoting-by-revert, tick counting, and TWAP helpers.
- [x] Keep string, SVG, and byte utility comments concise while documenting their business consumer.
- [x] Inspect the diff and confirm only comments changed.

### Task 6: Universal Swap Router

**Files:**
- Modify: production files under `contracts/swap-router/`, excluding `interfaces/` and `test/`.

- [x] Explain V2/V3 route composition, contract-balance sentinels, recipient sentinels, slippage checks, payment fees, approvals, and multicall behavior.
- [x] Distinguish this router's extensions from the base V3 periphery router.
- [x] Inspect the diff and confirm only comments changed.

### Task 7: Mechanical And Build Verification

**Files:**
- Verify: all modified Solidity files and documentation.

- [x] Run `git diff --check`; exit code 0.
- [x] Run `forge fmt --check`; existing repository formatting drift outside this change prevents a clean full-tree result.
- [x] Run `forge build --force`; exit code 0.
- [x] Review `git diff --stat` and zero-context executable-line filtering to catch accidental executable changes.
- [x] Confirm no differences outside comments and whitespace; only two unchanged statements with rewritten trailing comments were reported.
