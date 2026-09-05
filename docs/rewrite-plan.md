# 10bucks Selective Rewrite Plan

> **Status: approved planning baseline; runtime work has not started.** This plan replaces legacy behavior without backward compatibility or parallel production paths.

## 1. Outcome

Deliver a responsive, deterministic, keyboard-first window manager for the current built-in display and supported macOS/Hammerspoon environment, with:

- stack and two-column layouts behind a real extension interface
- stable per-Space ordering/grouping
- event-driven lifecycle, chooser backend, and status bar
- real native regular Space operations
- generic ordered rules and one-time fullscreen-on-create policy
- native minimize/hide/manual-fullscreen restoration semantics
- explicit invariants, live POC evidence, and performance gates
- simpler configuration and bindings

Success is not “all current tests pass.” Success is that approved invariants pass pure/sequence tests, live app-matrix scenarios, and latency/query budgets.

## 2. Current audit

At the planning baseline:

- production/config-example Lua: roughly 3,138 lines
- tests: 175 passing
- coupled control plane:
  - `engine.lua`: 744 lines
  - `state.lua`: 344 lines
  - `window_repository.lua`: 477 lines
  - `lifecycle.lua`: 160 lines
  - total: 1,725 lines, about 55% of production Lua
- engine uses 19 state methods, 18 repository methods, and 17 workspace methods
- two permanent timers run at 150 ms (bar) and 250 ms (reconciliation)
- an untracked `10bucks.spoon/lib/layout_transition.lua` is a prior incomplete experiment and is not part of the approved design

### Verified legacy defects/false contracts

- `reflow()` prunes durable state using a transient eligible/visible snapshot.
- reconciliation treats `_orderedwinids()` absence as death even though covered live stack members can be absent.
- tests fake onscreen IDs as all live IDs and endorse destructive pruning.
- chooser and global previous-window history include unmanaged windows, contrary to approved scope.
- numbered desktop shortcuts create missing labeled Spaces; approved behavior is focus-only native positions.
- stable custom Space labels persist through `hs.settings`; approved numbering is native positional.
- bar tests require `mainMenu`, despite live evidence that `overlay` is needed for reliable pixels.
- bar repeatedly queries/renders from a 150 ms timer.
- minimize removes membership rather than retaining an exact unavailable slot.
- mutable admission, focus, pruning, projection, and effect logic are mixed in the engine.
- state and engine are fixed around exactly two columns instead of layout modules.
- bindings/config tests spend substantial surface on legacy validation details.

## 3. Chosen strategy

### Selective clean rewrite

Rewrite the coupled control plane and native observation ports. Retain/tidy only leaf behavior after POC confirms it:

| Area | Strategy |
|---|---|
| reducer/state/effect planner | clean rewrite |
| lifecycle/window observation | clean rewrite after POC-001 |
| layout logic | clean stack + columns modules |
| workspace model | rewrite to native positional |
| rules | unified clean rewrite |
| bar lifecycle | rewrite; reuse visual primitives selectively |
| chooser | keep `hs.chooser` UI; replace backend |
| bindings/config | simplify directly |
| pure geometry | retain if target tests confirm |
| packaging/install/release | retain unless slice requires change |

Do not tidy every legacy abstraction merely because it exists. Use tidy-first only when a small behavior-preserving extraction creates a required seam more cheaply than direct replacement.

### No dual production path

- POC branches are disposable.
- Replacement code may be developed in isolation before an import/composition swap.
- Runtime invokes one implementation only.
- The completed slice deletes its replaced files/functions and obsolete tests.
- No `v1/v2`, compatibility adapter, or permanent feature flag.

## 4. Documentation and continuity artifacts

Canonical documents:

- [`invariants.md`](invariants.md) — normative contracts
- [`architecture.md`](architecture.md) — target design
- [`performance.md`](performance.md) — release budgets
- [`macos-settings.md`](macos-settings.md) — environment
- [`pocs/README.md`](pocs/README.md) — evidence plan
- root [`AGENTS.md`](../AGENTS.md) — agent workflow

Every implementation slice updates:

- invariant status/changes
- POC result and decision
- changed/deleted legacy surface
- verification commands/results
- next intended slice

Checkpoint only green, live-validated vertical behavior. Cheap rewind is branch/commit reset, not compatibility code.

## 5. Stage 0 — Baseline and plan lock

### Goal

Make the target unambiguous before runtime changes.

### Work

- Land this documentation set.
- Record baseline test/performance/app state without claiming correctness.
- Classify legacy tests by behavior/module as `retain`, `replace`, or `delete`; individually inspect only candidates whose contract may survive.
- Record the untracked/incomplete layout transition experiment; do not integrate it.
- Choose branch/checkpoint naming for POCs and implementation slices.

### Verification

- docs cross-links resolve
- target versus current status is explicit
- `lua tests/run.lua` baseline recorded
- working tree review confirms runtime unchanged

### Exit

No blocking semantic question remains; POC thresholds are fixed before tests begin.

## 6. Stage 1 — Prove macOS/Hammerspoon substrate

Run POCs in [`pocs/README.md`](pocs/README.md):

1. **POC-001:** events/liveness
2. **POC-002:** Space topology/operations
3. **POC-003:** overlay bar/handoff
4. **POC-005A:** creation/bootstrap readiness and manage/exclude decision
5. **POC-007:** environment settings/doctor feasibility

The user participates in guided app actions.

### Platform gate

If Hammerspoon passes, freeze selected adapter contracts. If an intrinsic boundary fails, run conditional POC-008 for only that boundary. Do not start the control-plane rewrite on unproved event/liveness assumptions.

### Exit

Recorded evidence selects:

- event source and authoritative destruction path
- independent lifecycle-condition/derived-availability behavior
- startup discovery scope and admission readiness
- targeted manual Space-move/membership detection
- existing-Space switching mechanism
- overlay/bar behavior and appearance signal
- required settings and doctor feasibility
- whether any minimal native adapter is justified

## 7. Stage 2 — Transaction/layout walking skeleton POC

Run POC-004 before replacing the complete core.

### Goal

Prove the approved reducer → commit → project → effect loop on real windows with both layouts' critical transitions.

### Work

- Implement disposable/minimal pure models for normalized events and both layouts.
- Replay synthetic sequences and live Terminal/Chromium traces.
- Count frame writes and API queries.
- Exercise stale focus callbacks, covered windows, minimize, and manual frame drift.

### Do not

- integrate a generalized legacy `layout_transition.lua`
- preserve old mutable state APIs
- build a shadow runtime

### Exit

POC-004 passes every stated threshold and yields the final minimal layout interface.

## 8. Stage 3 — Replace control plane and layouts

This is the coherent rewrite boundary. Develop on one dedicated implementation branch; swap once; delete legacy control-plane paths in the same completed slice.

### New responsibilities

- pure manager reducer/state with explicit display identity (one accepted display in MVP)
- transaction runtime and effect planner/executor
- Hammerspoon window adapter selected by POC-001
- stack layout module
- columns layout module
- managed-only focus history
- invariant validator for tests/development

### MVP behavior in this stage

- active-first startup/bootstrap and deferred discovery of uncertain inactive/minimized/hidden windows
- normalized readiness plus manage/exclude policy selected by POC-005A (fullscreen effects remain later)
- stack/columns cycling and inactive-state retention
- stable focus/navigation/grouping/divider/swap/move
- create/destroy/focus plus independent minimize/restore/hide/unhide conditions
- same-Space frame drift and next-boundary reflow
- no destructive polling
- actual-versus-managed focus separation; focus may trigger a targeted probe but only an independent idempotent readiness event may admit
- deterministic focus recovery and concrete rapid-command desired-selection policy

### Delete/replace

- legacy `engine.lua`, `state.lua`, `lifecycle.lua`, and broad repository contracts once swapped
- `reconcileActiveWorkspace()` and 250 ms timer
- `_orderedwinids()` liveness path
- per-ID `hs.window.get()` layout/recovery loops
- focus-as-admission behavior
- state mutation from `reflow()`
- obsolete engine/state/lifecycle/repository tests
- incomplete layout transition experiment from the implementation branch, subject to normal untracked-work safeguards

### Tests

- reducer event sequences by invariant ID
- stack/columns contract tests
- seeded generated sequences without external property-test dependency
- fake observations with independent alive/visible/onscreen/Space/availability flags
- effect/query/frame-write counts
- adapter tests from POC-001 traces

### Live acceptance

Terminal + Chromium first, then full representative app matrix for core lifecycle.

### Exit

- one runtime path
- no permanent lifecycle reconciler
- both layouts usable
- performance gates pass
- replaced code/tests gone

## 9. Stage 4 — Replace workspace behavior

### Preconditions

POC-002 passed; core has explicit Space events and per-Space state.

### Work

- replace stable labels with native regular positions
- regular/fullscreen topology adapter
- numbered focus-only commands
- cyclic positional previous/next
- dedicated create-next-and-focus command
- internal current/previous confirmed regular Space history
- empty deletion destination order:
  1. previous live managed window
  2. previous regular desktop
  3. adjacent left then right
- previous-window deletion candidate used only with confirmed non-source ownership; skip absent/uncertain/source candidates, and abort if an issued destination fails to depart
- after destination confirmation, a fresh source existence/inactivity/emptiness check immediately before removal; abort on changed/uncertain facts
- serialized/coalesced desktop navigation with relative arithmetic based on pending desired destination, structural-operation rejection, and late-completion reconciliation
- external create/delete/reorder handling
- manual window movement source removal + destination admission

### Delete

- `hs.settings` workspace label persistence/cache
- requested arbitrary numbered-label creation
- focus-or-create numbered command
- previous-focused behavior from `p` (history remains internal only)
- workspace selection modal and cancellation state
- false workspace tests

### Live acceptance

- occupied/empty Spaces
- fullscreen Spaces interspersed
- create/delete/manual reorder
- previous-window/previous-desktop deletion fallback
- rapid command replacement/timeouts

### Exit

Native positions/bar/commands agree after every topology event; no ghost scope remains.

## 10. Stage 5 — Rules and native fullscreen

### Preconditions

POC-005A already fixed readiness/admission before Stage 3; POC-005B native fullscreen scenarios now pass.

### Work

- reuse normalized creation/bootstrap readiness from Stage 3
- complete ordered first-match actions with fullscreen-on-create
- retain generic eligibility/capability policy
- `manage`, `exclude`, `nativeFullscreenOnCreate`
- one-time rule application
- spawn-fullscreen no-slot lifecycle and failure fallback
- manual fullscreen exact-slot retention
- removed-source invalidation/new destination admission
- configurable native fullscreen toggle command

### Delete

- separate exclusion lists/fullscreen matcher/filter policy if superseded
- app-specific default exclusions not expressible generically
- pending fullscreen logic that lives outside transactional state/effects
- creation/focus paths that rematch rules
- obsolete fullscreen tests

### Acceptance

No spawn-rule window receives a tiled flash; manual fullscreen round trip restores exact placement; source removal/new admission works.

## 11. Stage 6 — Cached chooser and global previous focus

### Preconditions

POC-006 passes.

### Work

- stable chooser-rank read model
- event-updated title/application/availability/Space fields
- app-icon cache by bundle ID
- managed-only chooser/history
- minimized unminimize, hidden app unhide, native fullscreen and cross-Space focus paths
- preserve `hs.chooser` fuzzy and observed `Cmd+1…9` UI behavior

### Delete

- `allLiveWindows()` chooser path
- broad picker filter
- unmanaged/floating history inclusion
- per-show metadata/icon enumeration
- picker-focus admission guards made unnecessary by FOCUS-003

### Acceptance

Chooser invocation meets p95 budget with slow apps open and performs zero global scans. Surviving row order never changes.

## 12. Stage 7 — Event-driven bar

### Preconditions

POC-003 passed; core exposes immutable bar view data.

### Work

- semantic bar view model
- separate formatter and canvas renderer boundary
- overlay all-regular-Spaces canvas
- state/focus/title/Space/appearance/screen-driven updates
- minute-boundary clock
- canvas mouse enter plus temporary hidden-state pointer tracker
- diffed render/show/hide behavior
- actual unmanaged focused title plus managed active-stack count

### Delete

- 150 ms refresh timer/config
- repeated `focusedWindow()`/Space queries in rendering
- `mainMenu` level assertion/behavior
- repeated show/reorder calls
- legacy bar tests that encode polling/window level

### Acceptance

All BAR invariants and performance gates pass across regular/fullscreen Spaces, Mission Control, theme changes, and pointer handoff.

## 13. Stage 8 — Config, commands, bindings, and slop deletion

Some config changes are required earlier to integrate slices; this stage completes simplification and removes transitional schema.

### Target config shape

- ordered unique enabled layouts and default layout
- per-layout options (columns ratio/bounds/step; shared gaps where appropriate)
- ordered rules
- bar appearance/content options actually consumed by MVP
- declarative command-to-hotkey bindings

### Work

- thin command registry/bindings
- add create Space and native fullscreen commands
- relative group navigation (`h`/`l`) through layout capability
- keep explicit reflow
- actionable semantic validation only
- update shipped example and README

### Delete

- managed frame `animationDuration`
- success `statusDuration`/alerts
- workspace chooser action
- focus-or-create numbered actions
- hidden/unused `newWorkspace` mismatch
- unused `toggleManaged` until explicit floating story
- bespoke validation/tests that do not protect a user contract

### Acceptance

Every documented command is configurable, duplicate/invalid bindings fail clearly, and binding code contains no behavior.

## 14. Stage 9 — Hardening and release readiness

### Work

- run full guided app matrix
- run seeded event-sequence tests at scale
- run all performance benchmarks with query/effect counters and next-key service probes during AX/Space work
- A/B required macOS settings and finish `macos-settings.md`
- add read-only doctor only if POC-007 says detection is reliable/cheap
- remove POC code/dead modules/unused config/tests
- inspect module dependency graph and production line growth
- update README installation/controls/troubleshooting, including the active-first/discovered-only cold-start chooser limitation
- package and dogfood before release

### Release gate

- every target invariant is implemented, explicitly deferred, or revised with user approval
- no unexplained permanent timer/poll
- no app-specific production branch
- one runtime implementation
- POC results and benchmark data committed
- full pure suite passes
- live matrix passes
- package/install checks pass

## 15. Test strategy

### Retain selectively

Likely candidates only after contract review:

- pure geometry frame tests
- Lua config-file loading/error basics
- `hs.chooser` rendering/fuzzy integration behavior
- packaging/release tests

### Replace

- engine/state/lifecycle/repository/workspace/bar tests tied to legacy APIs
- broad picker/history expectations
- stable label/focus-or-create tests
- main-menu/polling assertions
- onscreen-as-live reconciliation tests

### New test qualities

- test names reference invariant IDs
- reducer tests assert complete next state, not mutation call order
- sequence tests include real callback order variants from POCs
- adapters have contract fakes, not fake macOS semantics
- generated sequences verify uniqueness/membership/selection/order invariants
- performance tests assert query/frame/render counts in addition to wall time

## 16. Extension seams versus deferred implementation

Probable extension must influence boundaries now:

- layouts implement one interface
- bar formatter is separate from rendering/lifecycle
- rules are ordered actions
- commands are independent of hotkeys
- Hammerspoon/macOS effects sit behind ports
- display identity/work area is explicit even though only one display is accepted

But MVP does not implement:

- a third layout
- a general plugin loader
- arbitrary third-party bar components
- floating state/actions
- CLI dispatch
- multi-display state

A seam is successful when the likely feature can be added without untangling the core, not when unused generic code already exists.

## 17. Follow-up backlog

Ordered candidates after MVP evidence/dogfooding:

1. one-shot Hammerspoon reload snapshot, with immediate deletion and no schema migration
2. explicit managed floating mode/toggle
3. multi-display POC and state extension
4. CLI/skhd adapter if latency can be avoided/accepted
5. dedicated regular desktop policy for spawn-fullscreen exit
6. configurable bar format/components
7. third layout to validate/evolve the layout interface

Each follows the same POC-first, one-runtime-path policy.
