# 10bucks Selective Rewrite Plan

> **Status: approved implementation plan; production runtime work has not started.** This is the shortest path to a less sloppy, more reliable engine and cleaner architecture. It replaces legacy behavior directly: no compatibility layer, shadow runtime, or broad pre-implementation macOS certification.

## 1. Outcome and boundaries

Deliver a deterministic, keyboard-first manager for the supported built-in display with a small functional core, event-driven adapters, stack and columns layouts, cached chooser/bar data, and native regular-Space operations.

The target is not a claim that legacy behavior already meets the contracts. The target is the invariants in [`invariants.md`](invariants.md). Production behavior is unchanged by this documentation revision.

Success for each replacement is:

1. pure invariant/sequence coverage for the slice;
2. one direct composition swap to the replacement;
3. targeted live acceptance and the applicable performance measurement; and
4. deletion of the replaced production path and obsolete tests in that same slice.

Chromium and the broader application matrix are **Deferred** from adapter certification. They are ordinary slice acceptance and dogfood coverage, never app-specific production policy. `WIN-008` remains binding.

## 2. Current audit

At the planning baseline:

- production/config-example Lua: roughly 3,138 lines; tests: 175 passing;
- the coupled `engine.lua`, `state.lua`, `window_repository.lua`, and `lifecycle.lua` control plane is roughly 1,725 lines;
- permanent 150 ms bar and 250 ms reconciliation timers run;
- a prior audit once noted an untracked `10bucks.spoon/lib/layout_transition.lua` experiment; it is not present in this baseline and is not approved design.

### Verified legacy defects and rejected contracts

- Reflow and reconciliation destructively infer death from eligible/visible or `_orderedwinids()` snapshots.
- Repeated per-ID `hs.window.get()` in reflow can block badly in slow AX applications.
- Mutable admission, focus, pruning, projection, and effects are coupled.
- Minimize removes membership; chooser/history include unmanaged windows; bar polls; native Space labels persist as settings.
- Tests endorse several of those false contracts.

These are replacement targets, not reasons to preserve an old API while improving internals.

## 3. Engineering decisions now

### Window adapter

**Target adapter policy:** the initial window adapter uses direct application and UI-element Accessibility events:

- direct application watcher events normalize termination, hide, and unhide;
- direct UI-element/window events normalize readiness, title, minimize/restore, fullscreen, focus-related observations, and destruction;
- the reducer treats normalized `AXUIElementDestroyed` and application-termination observations as removal facts;
- missed, delayed, contradictory, or unavailable observations retain uncertainty non-destructively. They may leave a stale member; they must not delete a possibly live one.

`hs.window.filter` is rejected as the primary adapter. Its recorded POC-001 comparison evidence remains useful history, but its expensive/opaque refresh risk does not justify making it the lifecycle authority. `_orderedwinids()`, z-order, visibility, and eligible/onscreen snapshots remain forbidden liveness evidence. There is no destructive reconciliation and no permanent liveness polling.

This **Target adapter policy** preserves `STATE-004`, `STATE-005`, `LIFE-004`, and `WIN-005`: its selected explicit removal observations remove; uncertainty does not.

### Evidence discipline

The former broad POC-001 certification protocol is **superseded**; it has no broad pass. Its recorded observations remain observations; failed thresholds remain failed and incomplete samples remain incomplete. The removal rule is a **Target adapter policy**, not a verified delivery/reliability conclusion. See [`pocs/001-window-events-liveness.md`](pocs/001-window-events-liveness.md).

POCs are now just-in-time, minimal evidence for an unresolved private or undocumented mechanism at the slice that needs it. Pure reducer, layout, transaction, and direct-AX adapter implementation starts now. A POC is not a precondition merely because an area touches macOS.

### One replacement path

Implementation may be built and tested as pure modules before composition, but it must not be composed beside the legacy runtime. Each completed vertical slice swaps once and deletes the legacy production path and obsolete tests it replaces. Git history is rollback.

## 4. Canonical documents and checkpoints

- [`invariants.md`](invariants.md): normative contracts; revise only deliberately.
- [`architecture.md`](architecture.md): target module boundaries and selected adapters.
- [`performance.md`](performance.md): release budgets and measurement method.
- [`macos-settings.md`](macos-settings.md): supported environment.
- [`pocs/README.md`](pocs/README.md): narrowly scoped, just-in-time evidence index.
- root [`AGENTS.md`](../AGENTS.md): slice and evidence workflow.

A green checkpoint records the changed/deleted surface, invariant IDs, pure checks, targeted acceptance, relevant benchmark, and the next slice. It does not require a broad app matrix or unrelated POC to be complete.

## 5. Vertical implementation slices

### Slice 1 — Pure state, reducer, and transaction seam

**Goal:** establish the engine without changing the active runtime.

- Implement primitive `ManagerState`, normalized-event reducer, invariant validator, transaction queue, and effect-intent boundary.
- Implement stack and columns reducer/projector interfaces with explicit display/Space identity.
- Add reducer, layout, and generated-sequence tests by invariant ID, including independent liveness/visibility/availability facts.
- Keep modules uncomposed; do not create a shadow runtime or preserve mutable legacy state APIs.

**Green checkpoint:** pure suite is green; projection has no state mutation; next state commits before effects in tests. No live POC is required.

### Slice 2 — Direct-AX lifecycle adapter and complete composition swap

**Goal:** replace the coupled legacy runtime in one executable vertical swap; no Engine-shaped compatibility façade is permitted.

- Normalize direct application/UI-element events into the Slice 1 reducer. The **Target adapter policy** treats normalized destruction and application-termination observations as removal facts; missed or uncertain observations retain membership.
- Add minimal immutable normalized metadata and the pure generic `RULE-002` admission decision: reject self-process, non-standard/modal/transient, or non-movable/non-resizable candidates; otherwise `manage`. Focus never admits. Slice 2 neither calls nor retains `WindowRepository` eligibility methods.
- Implement create/destroy, focus separation/recovery, minimize/restore, hide/unhide, stable ordering, same-Space reflow boundaries, and zero-duration deduplicated frames.
- Replace `init.lua` construction and start/stop/teardown ownership with runtime, direct-AX, workspace-context, bar-read-model, chooser, and command owners. Deliver actual focus plus committed read-model updates to the retained bar renderer; it must not read old engine/repository/state APIs.
- Replace bindings with a command registry that emits reducer commands. Migrate layout/focus/divider/move/swap/reflow and chooser actions; deliver a cached managed-only chooser backend and focus history from reducer events, never `allLiveWindows()` at show time. Explicitly delete unsupported legacy workspace/modal/create/delete/numbered actions and `toggleManaged` until their Slice 4 or deferred replacements exist.
- Provide a minimal workspace-context port (display ID, confirmed active regular Space, work area, and change observation) for the core/bar; Slice 4 may improve native operations but cannot call old engine/repository/state APIs.
- Swap composition once; delete legacy `engine.lua`, `state.lua`, `lifecycle.lua`, and `window_repository.lua`, their consumers/contracts, destructive reconciler/timer, snapshot liveness logic, per-ID reflow lookups, and obsolete tests.
- Inventory and delete runnable POC-001 observer, fixture, controller, instrumentation, and tests in this slice. Retain only historical Markdown evidence under `docs/pocs/` and any named result documents; no runnable diagnostic is retained without a separately documented owner, invocation boundary, purpose, and measured negligible idle cost.

**Acceptance:** targeted Terminal/manual smoke for lifecycle, commands, cached chooser, retained-bar read model, and frame path, plus query/frame counters. Chromium is optional ordinary acceptance here, not a blocker or special case.

**Green checkpoint:** one runtime path; init/start-stop, bindings, chooser, and retained bar use only replacement ports; no permanent lifecycle poll or runnable POC-001 surface remains; replaced paths/tests gone; relevant `PERF-*` checks pass.

### Slice 3 — Configured ordered rules

**Goal:** add user-configured first-match policy without reopening generic admission or chooser ownership.

- Add ordered pure `manage`, `exclude`, and `nativeFullscreenOnCreate` decisions over Slice-2 normalized metadata; the fullscreen action remains a decision until Slice 5 effects.
- Replace any superseded configuration/tests. Do not reclassify a window after its one ready-time decision.

**Green checkpoint:** `RULE-001`, `RULE-003`, and `RULE-004` sequence coverage is green; Slice-2 generic policy and cached chooser remain the only admission/read-model path.

### Slice 4 — Workspace rewrite

**Precondition:** before implementing native Space operations, run one minimal POC for the unresolved switching/topology/deletion mechanism. **POC-002 must not start now.**

- Replace labels with native regular-Space positions, topology events, per-Space state, numbered focus, cyclic navigation, create, deletion safeguards, and external-change reconciliation.
- Delete settings-backed labels, focus-or-create numbers, workspace modal, and obsolete tests.

**Green checkpoint:** native topology acceptance and Space-specific benchmark pass; one runtime path remains.

### Slice 5 — Native fullscreen effects

**Precondition:** immediately before fullscreen effects, run only the minimal POC needed for unresolved fullscreen transition/confirmation behavior.

- Add fullscreen-on-create effects, manual fullscreen slot retention, source invalidation, and toggle serialization.
- Delete superseded fullscreen paths/tests.

**Green checkpoint:** `FS-*` acceptance and transition measurements pass; no tiled flash for spawn-fullscreen.

### Slice 6 — Event-driven bar

**Precondition:** immediately before bar replacement, run only the minimal overlay/handoff POC needed for unresolved canvas behavior.

- Add semantic bar view model, formatter/renderer boundary, overlay lifecycle, event updates, minute clock, and bounded temporary pointer tracking.
- Delete the 150 ms refresh timer, `mainMenu` behavior, repeated rendering queries, and obsolete bar tests.

**Green checkpoint:** `BAR-*` acceptance and render/query budgets pass.

### Slice 7 — Commands, configuration, and hardening

- Finish thin command bindings, semantic config validation, and remove legacy configuration slop.
- Run broader app matrix, settings review/doctor decision, package checks, longer sequence runs, and dogfood.
- Treat settings work as acceptance/hardening, not a blocker for Slices 1–3. The chooser benchmark belongs to Slice 2 acceptance; `POC-007` may support a read-only doctor only when that work is undertaken.

**Release gate:** all invariants are implemented, deliberately revised, or explicitly deferred; pure suite and applicable targeted acceptance/benchmarks pass; no permanent unexplained poll, app-specific production branch, or duplicate runtime remains.

## 6. POC schedule

| Need | When | Scope |
|---|---|---|
| Window lifecycle | Superseded historical hypothesis; no broad pass | POC-001 informs the Target direct-AX removal policy; no broad recertification. |
| Space topology/operations | Immediately before Slice 4 | Minimal operation/topology question only; POC-002 does not start now. |
| Fullscreen | Immediately before Slice 5 | Transition/confirmation behavior needed by fullscreen effects. |
| Bar | Immediately before Slice 6 | Overlay/handoff behavior needed by bar adapter. |
| Settings/doctor | Slice 7 hardening | Detectability and documentation, not core-engine gating. |
| Chooser benchmark | Slice 2 acceptance/hardening | Cached-backend budget, not a standalone platform gate. |

POC-004 is `superseded` as a standalone exercise. Its useful content is Slice 1 pure coverage and Slice 2 targeted acceptance; no disposable transactional-layout runtime is composed.

## 7. Test and acceptance strategy

Replace, rather than retain, tests that encode snapshot-as-liveness, polling, legacy labels, unmanaged picker/history scope, or mutable engine APIs. Retain only leaf tests after contract review.

New tests assert complete reducer state, layout contracts, independent lifecycle conditions, callback-order variants already observed, and query/effect/frame counts. Pure fakes model adapter facts, not imaginary macOS guarantees.

Targeted acceptance happens at each vertical swap. The full Terminal/Chromium/Slack/Signal/Thunderbird/Claude/Zoom matrix is deferred to Slice 7 dogfood and release readiness. A failure there may motivate a generic adapter correction backed by narrow evidence; it never creates an app-specific production conditional.

## 8. Deferred work

The existing invariant deferrals remain: multiple displays, managed floating, CLI/skhd, persistence/reload snapshots, dedicated desktop after spawn-fullscreen exit, third-party plugin distribution, and version support shims. No implementation slice adds them merely to make an abstraction look complete.
