# Issue Draft: Add simulation troubleshooting guidance to getting-started.md

> **Target repo**: https://github.com/nishuzumi/moss
> **Submission URL**: https://github.com/nishuzumi/moss/issues/new?template=feature_request.md
> **Title**: `[feature] Add simulation troubleshooting guidance to getting-started.md`
> **Labels**: `enhancement` (auto-assigned by template)

---

## Problem

The [Getting started](./docs/getting-started.md) guide walks through the happy path of the `discover -> load -> action -> simulate` workflow across 12 sections, but Section 8 (Simulate and inspect Receipts) leaves three practical gaps that new users hit during onboarding:

### 1. RPC requirement for `debug_traceCall` is not documented

Section 1 says the examples "read live Monad mainnet state" and Section 2 passes `MOSS_RPC_URL` in code, but neither explains that **simulation requires an RPC endpoint that supports `debug_traceCall` with `callTracer` and `prestateTracer`**.

A user who sets `MOSS_RPC_URL` to a third-party RPC that lacks `debug_traceCall` support will see `TRACE_FAILED` in the warnings array and have no guidance on what went wrong or how to fix it. The default `https://rpc.monad.xyz` works, but users who switch to a custom endpoint for latency or rate-limit reasons have no warning.

### 2. Warning codes are described in prose but not listed

Section 8 currently says:

> A revert, trace failure, state-chaining failure, Receipt error, or coverage mismatch produces a terminal Warning.

This describes the *categories* but does not list the actual warning codes that appear in `simulation.results[].warnings`. A user who sees `CHANGE_COVERAGE_MISMATCH` or `STATE_CHAIN_FAILED` in their output has to read the simulator source code to understand what it means.

### 3. `slippage` unit convention is easy to miss

Section 7 uses `slippage: 50` in the code example. The basis-points convention (`50 = 0.5%`, not `50%`) is explained in Section 5's `load` output, but a user who jumps directly to Section 7's code block may miss it and assume 50 means 50% slippage.

## Proposed solution

Add a short **"Troubleshooting simulation"** subsection at the end of Section 8 (or as a new Section 8.5) covering:

**a) RPC requirements**

A brief note that simulation uses `debug_traceCall` with `callTracer` + `prestateTracer`, that the default `https://rpc.monad.xyz` supports this, and that if `TRACE_FAILED` appears the user should verify their custom RPC endpoint supports these tracing methods.

**b) Warning code reference**

A compact table mapping each warning code to a one-line description and the most common cause:

| Code | Meaning | Common cause |
| --- | --- | --- |
| `REVERTED` | Transaction reverted during simulation | Invalid parameters or insufficient balance |
| `TRACE_FAILED` | RPC could not provide trace evidence | RPC endpoint does not support `debug_traceCall` |
| `CHANGE_ORDER_UNAVAILABLE` | Cannot prove exact event ordering | RPC tracer limitations |
| `RECEIPT_FAILED` | Protocol could not parse Changes into a Receipt | Protocol adapter bug or unexpected contract behavior |
| `CHANGE_COVERAGE_MISMATCH` | Receipt omitted, duplicated, or reordered Changes | Protocol adapter bug |
| `STATE_CHAIN_FAILED` | Later transaction state could not derive from earlier | Inter-transaction dependency issue |

**c) Parameter unit reminder**

A one-line callout near the Section 7 code example: `slippage` is in basis points (`50` = `0.5%`), and `amountIn`/`amountOut` are decimal strings to avoid precision loss.

## Alternatives considered

- **Standalone FAQ document** (#77 proposed this for Chinese newcomers and was closed as not planned). Integrating into the existing getting-started.md is more discoverable and aligns with the maintainer's preference.
- **Inline comments in code examples only**. Less discoverable than a dedicated subsection when a user is debugging a `TRACE_FAILED` error.

## Additional context

- The `CONTRIBUTING.md` already documents toolchain constraints (Stage-3 decorators, TS 5.9.x pin, `minimumReleaseAge: 1440`). A cross-reference from getting-started.md Section 11 ("Start a Protocol package") to these constraints would also help new contributors, but that is a separate concern from simulation troubleshooting.
- The `mcp-tools.md` and `agent-skill.md` docs describe the Agent-facing safety rules but do not list the warning codes either. A reference table in getting-started.md would be the canonical location since that is the first doc new users read.
