# POC Protocol and Just-in-Time Evidence Index

> **Status: evidence policy for the rewrite.** A POC proves one unresolved macOS/Hammerspoon mechanism when the implementation slice needs it. It is not a broad pre-implementation certification program.

POCs use disposable code or instrumentation and never create a second production path. Pure reducer/layout/transaction work does not need a POC. Scheduled canary acceptance validates a composed implementation; it is not another POC or a broad certification program. During a canary, stable and development runtimes are never active simultaneously. A completed replacement deletes its old production path and obsolete tests in the same slice.

## Evidence rules

- Use **Verified**, **Target**, **Hypothesis**, and **Deferred** precisely.
- Preserve recorded evidence. A missed threshold, interrupted sample, or unmeasured case remains so; do not call it passed after changing scope or threshold.
- Before recording a failure as platform evidence, independently inspect underlying output for harness, stale-state, procedure, and analysis defects.
- A POC command must use a timeout of at most 120 seconds unless the human explicitly approves a longer, explained, indivisible step. Split long work into observable steps.
- A POC may not introduce permanent polling. A targeted safety check requires recorded evidence of a silent gap and must remain non-destructive.
- POC code is removed after its purpose unless a result names a POC-only diagnostic owner, ongoing use, and negligible idle cost.

## Required result format

```markdown
# POC-NNN — Title

## Status
hypothesis | passed | failed | superseded

## Decision enabled
The narrow production choice that requires this result.

## Hypothesis
One falsifiable statement.

## Environment
- macOS build:
- architecture/display:
- Hammerspoon version:
- 10bucks commit/branch:
- relevant System Settings:
- applications/versions:

## Procedure
Exact setup and guided actions.

## Instrumentation
Events, timestamps, query/effect counts, and commands captured.

## Acceptance threshold
Fixed measurable pass/fail criteria.

## Results
Raw/summary measurements, unexpected sequences, and failures.

## Conclusion
The narrow fact proved; distinguish observation from inference.

## Production consequence
Chosen/rejected mechanism and remaining unknowns.

## Cleanup
Removed code or justified retained diagnostic.
```

Screenshots support visual findings only; they do not replace event or latency data. Do not commit private window titles, URLs, paths, messages, account information, raw AX values, or native IDs.

## POC-001 — Window events and liveness

**Status: `superseded`.** Historical **Hypothesis**; no broad pass. The canonical record is [`001-window-events-liveness.md`](001-window-events-liveness.md). It retains all prior fixture, direct-AX, filter, timing, interruption, and failed-threshold evidence without reinterpretation.

**Target adapter policy:** begin with direct application/UI-element AX events. The reducer treats normalized `AXUIElementDestroyed` and application-termination observations as removal facts; missed or ambiguous facts are retained as uncertainty. `hs.window.filter` is rejected as the primary adapter. `_orderedwinids()`, visibility, z-order, and eligible/onscreen snapshots are never liveness proof. No destructive reconciliation or permanent liveness poll is permitted.

This status does not claim that broad POC-001 criteria passed. In particular, recorded filter readiness failures, callback-budget misses, incomplete cold samples, and unmeasured representative-app cases remain unresolved historical evidence. Chromium is deferred to normal slice acceptance/dogfood, not a certification gate. Do not start another broad POC-001 run for the initial direct-AX implementation.

## POC-002 — Native Space topology and operations

**Status: deferred; must not start now.** Run only immediately before the workspace rewrite, and only to resolve the exact private/UI-automation question that remains after the core is ready.

**Decision needed:** choose a SIP-enabled existing-Space switching and topology-confirmation mechanism; validate the smallest needed create/delete and external-topology observations.

**Minimum scope:** native regular-Space positions versus fullscreen/tiled Spaces; operation acceptance versus watcher-confirmed completion; one chosen switch path; final source existence/inactivity/emptiness confirmation before deletion; and an instrumented next-key service observation during any blocking operation. Do not use this POC to certify every application or unrelated core behavior.

## POC-003 — Overlay bar and native handoff

**Status: deferred.** Run immediately before the bar rewrite if the existing overlay evidence does not answer the exact adapter question.

**Decision needed:** the smallest reliable overlay canvas configuration and pointer handoff behavior on regular versus native-fullscreen/tiled Spaces.

**Minimum scope:** pixels at the selected level, regular-Space/Mission Control behavior, fullscreen hiding, pointer handoff, and confirmation that event-driven rendering needs no permanent refresh timer.

## POC-004 — Transactional layout/effect loop

**Status: `superseded`.** The reducer → commit → project → effect design is implemented and tested directly in pure Slice 1, then accepted in the Slice 2 production replacement. No disposable layout runtime, shadow composition, Terminal/Chromium certification trace, or standalone POC-004 gate is authorized.

## POC-005 — Admission readiness and native fullscreen

**Status: deferred.** Slice 2 implements normalized metadata and the generic `RULE-002` manage/exclude decision with the direct-AX adapter. If a private/undocumented readiness mechanism blocks that slice, run only a minimal focused POC for that mechanism. Configured ordered rules arrive later.

Run the fullscreen portion immediately before fullscreen effects. It must answer only transition confirmation, failure/timeout, manual slot retention, and source-Space removal behavior needed for that slice. It must not broaden into an app matrix.

## POC-006 — Cached chooser and cross-Space focus

**Status: deferred.** Slice 2 composes the cached backend and proves it with pure query-count tests plus targeted acceptance. Benchmark ordinary chooser invocation, row stability, and restoration behavior at that swap; no standalone platform certification is required unless an unresolved private mechanism emerges.

## POC-007 — macOS settings and read-only doctor

**Status: acceptance/hardening, not a core blocker.** Run when settings documentation or a read-only doctor is being finalized. Classify only settings whose detectability and support consequences are needed. Documentation is sufficient if cheap reliable detection is not proved.

## POC-008 — Native boundary fallback

**Status: conditional.** Run only if a completed slice exposes an intrinsic direct-AX/Hammerspoon boundary that cannot meet the required generic behavior or budget. Build the smallest native experiment for that boundary; a tangled legacy runtime or Lua line count is not evidence for a wholesale native rewrite.

## POC-010 — Pre-existing fullscreen focus history

**Status: narrow observation passed; candidate acceptance pending.** [`010-fullscreen-focus-history.md`](010-fullscreen-focus-history.md) records confirmed native-fullscreen ownership with locked AX position, managed-history omission, and the resulting wrong previous target. It enables independent unplaced fullscreen readiness, not focus-driven admission, invented regular placement, or an app-specific exception. No broad fullscreen-effects or latency pass is claimed.

## POC-009 — Unchanged native focus confirmation

**Status: narrow mechanism observations passed.** [`009-focus-confirmation.md`](009-focus-confirmation.md) records a same-target command that remained pending without a callback, then a separate matching focus/read probe. These support one targeted post-effect confirmation read, not polling or confirmation from a stale Core. End-to-end acceptance and callback reliability are not established by those probes. The record also attributes Space-bootstrap blocking; no broad focus or performance pass is claimed.

## Slice cleanup gate

Before merging a replacement that used a POC, record the narrow result and decision, remove disposable code, retain only justified diagnostics, and copy a selected fact into architecture/performance/settings documentation where it changes a target contract. A POC never authorizes compatibility paths, app-specific production behavior, or a second runtime.
