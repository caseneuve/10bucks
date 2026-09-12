# Working on 10bucks

10bucks is an opinionated, keyboard-first tiling window manager for one current user. Correctness, latency, and maintainability outrank backward compatibility.

## Current status

The checked-in runtime is the legacy implementation. The documents below define a planned selective rewrite; they do **not** claim the current code already satisfies the target contracts.

Read these before changing runtime behavior:

1. [`docs/invariants.md`](docs/invariants.md) — normative user and state contracts.
2. [`docs/architecture.md`](docs/architecture.md) — target module boundaries and transaction flow.
3. [`docs/rewrite-plan.md`](docs/rewrite-plan.md) — POC-first replacement sequence.
4. [`docs/performance.md`](docs/performance.md) — latency and query budgets.
5. [`docs/macos-settings.md`](docs/macos-settings.md) — supported environment and required settings.
6. [`docs/pocs/README.md`](docs/pocs/README.md) — evidence standard for macOS behavior.

If code and target documentation disagree during the rewrite, do not silently “fix” either side. Identify whether the slice is still legacy or whether the target contract needs a deliberate revision.

## Shared work-state protocol

Agents working in a checkout that contains `.pi/WORK_STATE.md` MUST use it as the operational handoff:

1. Read it before planning or editing, then read every canonical document and handoff it names.
2. Verify its branch, HEAD, working-tree, and runtime-safety facts with local commands. Correct stale facts explicitly; do not silently trust them.
3. Before starting a step, update **Current step** with the agent/session, narrow scope, status, and timestamp.
4. After each reviewed checkpoint, commit, blocker, failed check, or change of next action, replace the relevant sections. Do not leave completion updates until a later agent.
5. Before the final response, update the timestamp, current status, completed work, exact checks/results, blockers, runtime-safety state, and one concrete next action.

Keep this file concise and current rather than appending a transcript. Retain only a short recent-checkpoint list. Use **Verified**, **Target**, **Hypothesis**, and **Deferred** precisely. Never put private window titles, URLs, messages, account data, raw AX values, or native IDs in it.

`.pi/WORK_STATE.md` is operational state, not a behavior contract. `docs/invariants.md`, `docs/architecture.md`, and `docs/rewrite-plan.md` remain authoritative. If several agents run concurrently, the orchestrator is the single state-document writer and consolidates worker results after reviewing them.

## Non-negotiable implementation rules

- Maintain one runtime path. Do not add shadow, legacy, compatibility, or indefinite feature-flag implementations.
- Backward compatibility is a non-goal. Git history is the rollback mechanism.
- Before relying on an unproved undocumented/private macOS behavior, run and record a live POC. Reuse existing recorded evidence instead of repeating POCs ceremonially.
- A finished replacement deletes the old production path and obsolete tests in the same slice.
- Never treat visibility, z-order, `_orderedwinids()`, or one eligible-window snapshot as proof of liveness.
- Durable state has one writer: the reducer. Queries, projection/reflow, rendering, and effect execution cannot mutate it.
- Commit complete next state before requesting frames, focus, fullscreen, or Space changes.
- Store primitive data in durable state, not `hs.window`, canvas, watcher, timer, or other Hammerspoon userdata.
- Focus may change selection and focus history; it may not admit a window or change stack order.
- App-specific behavior belongs in user rules, not production conditionals.
- Do not add permanent polling unless a recorded POC proves an event/reconciliation boundary cannot provide the behavior.
- Do not add an abstraction only for hypothetical reuse. Do preserve documented, probable extension seams: layouts, bar formatting/rendering, rules, commands, and macOS adapters.
- Do not preserve a false test contract to keep the suite green. Replace tests with approved invariant/sequence coverage.
- Preserve unrelated and untracked work. In particular, do not assume an untracked file is safe to remove merely because the plan does not use it.

## Slice protocol

For a slice that depends on an unproved macOS/Hammerspoon assumption:

```text
hypothesis → live POC → recorded pass/fail evidence
```

For every behavioral replacement:

```text
cite existing evidence where applicable
  → invariant/sequence test
  → direct replacement
  → targeted live acceptance + relevant benchmark
  → delete replaced code/tests
  → green checkpoint
```

### POC agent time and failure discipline

- A POC agent MUST NOT start a command with a timeout longer than 120 seconds, or start work expected to run longer than 120 seconds, without first stating the expected duration and reason and receiving explicit human approval. Hour- or day-scale defensive timeouts are forbidden. Split work into short, observable steps instead.
- A POC agent's failure report is not accepted as evidence by itself. Before recording or acting on a failure, the orchestrator MUST inspect the underlying trace/output and independently check for harness defects, stale state, operator/procedure errors, and analyzer mistakes. Safe deterministic re-analysis is allowed; another live action or changed threshold still requires the applicable approval. Classify the outcome as platform evidence only after this review rules out a false negative.

Do not require a new POC for ordinary pure implementation work whose platform assumptions are already proved. A behavior-preserving tidy-first change is allowed only when it creates a required replacement seam more cheaply than directly rewriting the coupled piece. It must not preserve a rejected contract.

## Evidence language

Use these labels in plans and reviews:

- **Verified:** observed in source, official API headers/docs, or a recorded live POC.
- **Target:** approved behavior not implemented yet.
- **Hypothesis:** must be proved before production design depends on it.
- **Deferred:** explicitly outside MVP.

Do not turn hypotheses into explanations of macOS behavior.

## Verification

Current pure-Lua suite:

```sh
lua tests/run.lua
```

During the rewrite, tests should reference invariant IDs from `docs/invariants.md`. Live behavior and performance are verified with the relevant POC procedure; fake unit tests are not substitutes for macOS evidence.
