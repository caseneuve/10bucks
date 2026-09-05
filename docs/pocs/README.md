# POC Protocol and Matrix

> **Status: required evidence plan.** No risky macOS/Hammerspoon behavior becomes production architecture before its POC passes.

POCs run on disposable branches. They are required for unproved platform assumptions, not repeated for ordinary pure implementation work already covered by recorded evidence. They may temporarily replace legacy code or use standalone instrumentation, but production must never keep two runtime paths. Failed POC code is deleted; findings remain here or in a sibling result document.

The user may participate in guided manual runs. Manual actions are often preferable to automation that changes focus/event timing and contaminates the behavior being measured.

## Required result format

Create `docs/pocs/NNN-short-name.md` from this structure:

```markdown
# POC-NNN — Title

## Status
hypothesis | passed | failed | superseded

## Decision enabled
What production choice depends on this result?

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
Measurable pass/fail criteria fixed before the run.

## Results
Raw/summary measurements, unexpected sequences, and failures.

## Conclusion
Pass/fail and the narrow fact proved. Separate inference from observation.

## Production consequence
Chosen adapter/algorithm, rejected approaches, and remaining unknowns.

## Cleanup
POC code removed or named reusable diagnostic retained with justification.
```

Screenshots may support a visual finding, but must not replace event/latency data. Do not commit private window titles or corporate information without redaction.

## POC-001 — Window events and liveness

### Decision

Choose `hs.window.filter`, direct `hs.application.watcher` + `hs.uielement.watcher`, or a narrower combination. Define authoritative destruction and manual Space-move detection. The POC-only fixture's separately gated [fixture--observer correlation handoff](../../pocs/001-window-events-liveness/CORRELATION-HANDOFF.md) defines a candidate public-AX identity experiment only; it authorizes no implementation or live action.

### Instrumentation

Timestamp and correlate:

- filter and direct AX events
- app launch/termination/hide/unhide
- focused/active Space
- `windowSpaces(windowId)` and `windowsForSpace(spaceId)` results
- visibility/minimized/fullscreen/role/subrole metadata
- callback duration and global AX calls

Comparison instrumentation is POC-only, not a production dual path.

### Guided matrix per representative app

1. create first and additional windows
2. focus/unfocus
3. close foreground, background, and last window
4. minimize/restore, including minimize → hide app → unhide app → restore in varied callback orders
5. hide/unhide app, including apps with a mix of minimized and non-minimized windows
6. enter/exit native fullscreen
7. manually move a window with Mission Control/title-bar/edge mechanisms available
8. quit/relaunch app
9. completely cover a stacked window
10. cold-start/reload with inactive-Space, minimized, hidden, and native-fullscreen pre-existing windows
11. rapidly repeat create/focus/close

### Pass

- covered windows are never inferred dead
- at least one authoritative destruction path exists, or a cheap targeted check is proved
- minimize/hide/fullscreen remain distinguishable
- manual movement is eventually detected without permanent global polling
- overlapping lifecycle conditions derive availability correctly regardless of callback order
- creation/bootstrap metadata and actual-Space ownership have a bounded readiness/discovery strategy
- callbacks remain within the performance contract

If all event paths have a proven silent gap, design the least frequent non-destructive targeted safety check and measure it. Never fall back to `_orderedwinids()` liveness.

## POC-002 — Native Space topology and operations

### Decision

Select existing-Space switch mechanism and prove positional numbering, create, delete, watcher timing, and external topology changes.

### Compare

1. `hs.spaces.gotoSpace()`
2. native macOS “Switch to Desktop N” shortcuts
3. a direct private adapter only if both fail and it works with SIP enabled/no privileged helper

### Matrix

- switch to occupied and empty regular Spaces
- cyclic previous/next behavior
- create next Space and focus it
- delete active empty Space after switching to chosen destination
- manually reorder/create/delete Spaces
- include fullscreen/tiled Spaces between regular Spaces
- manually move windows between regular Spaces
- concrete rapid sequences: `n,n` from desktop 1 desires 3; `n,p` desires 1; numbered focus replaces the pending destination
- chooser/previous-window requests during an existing switch, plus repeated previous-window before actual focus confirmation
- navigation attempts during create/delete, late completion, and cancellation
- a window arriving in the source after deletion starts but before removal
- a previous-window candidate known/unknown to resolve to source, and an issued candidate that fails to leave source
- a benign hotkey during Space animation/AX work to expose main-thread blockage
- Reduce Motion on/off if permitted

### Pass

- regular positions match native left-to-right order
- fullscreen/tiled Spaces are excluded
- operation acceptance and watcher-confirmed completion are distinguishable
- visual Space animation/settling is measured separately; Hammerspoon continues servicing instrumented input within the agreed budget
- final state after key repeat/coalescing matches the documented desired destination; repeated previous-window before confirmation targets the same history entry
- source/uncertain previous-window candidates are skipped before effects; failed issued departure aborts without cascading
- source existence/inactivity/emptiness is freshly checked immediately before removal; changed/uncertain state aborts
- failure/timeout leaves no Mission Control session or pending state stranded; late native changes reconcile as external facts
- accepted visual animation does not block servicing the instrumented hotkey beyond the performance gate

## POC-003 — Overlay bar and native handoff

### Decision

Prove one event-driven all-regular-Spaces canvas and remove legacy main-menu/polling behavior.

### Matrix

- `overlay` level with `canJoinAllSpaces`, `stationary`, and cycle behavior combinations
- every regular desktop, rapid switching, Mission Control, and App Exposé
- native fullscreen/tiled Spaces
- pointer enter, native menu-bar reveal, pointer exit, grace/show
- light/dark appearance change
- Hammerspoon console visible/hidden
- canvas reports shown but visual screenshot comparison

### Pass

- bar produces pixels on every regular Space and remains in Mission Control/App Exposé
- bar is absent on native fullscreen/tiled Spaces
- pointer reveal works without a permanent 150 ms timer
- temporary pointer tracking stops after handoff
- unchanged content causes no render/show/reorder
- appearance and minute clock update from events/one aligned timer

## POC-004 — Transactional layout/effect loop

### Decision

Prove the reducer → commit → project → deduplicated-effect shape before replacing the complete control plane.

### Scenarios

- one window then split-right admission
- third window enters active column before focus callback
- rapid and opposite focus/group commands, stale intermediate focus callbacks, and latest-request timeout
- close/minimize recovery ordering
- covered member absent from onscreen IDs
- same-Space manual resize followed by next synchronization boundary
- column swap/move/layout-cycle round trips
- temporarily unavailable entire column

### Pass

- invariant validation passes after every transaction
- focus callbacks never revise admission/group assignment
- no projection mutates state
- at most one frame write/window/transaction
- no temporary wrong-column frame
- final desired/actual selection follows the rapid-command policy
- live Terminal plus one Chromium app meet latency and next-key service budgets

## POC-005 — Admission readiness, rules, and native fullscreen lifecycle

This POC has two gates. **POC-005A** (metadata readiness, bootstrap discovery, manage/exclude decision, and proof that bootstrap is not creation) must pass before the control-plane adapter freezes in Stage 3. **POC-005B** covers native fullscreen effects before Stage 5.

### Decision

Prove creation/bootstrap readiness and one-time rule decisions first; then prove fullscreen request/failure/timeout, manual fullscreen slot retention, and source-Space removal behavior.

### Matrix

- declarative bundle/title rules and normalized predicate
- title initially empty then populated
- cold start with active/inactive-Space, minimized, hidden, and native-fullscreen windows
- focus on a previously undiscovered window: focus triggers only a targeted probe; independent duplicate/delayed readiness results admit at most once
- manage/exclude on pre-existing windows while `nativeFullscreenOnCreate` is suppressed
- request accepted/succeeded, synchronously failed, and timed out
- spawn-fullscreen exit → fresh normal admission
- manual fullscreen existing member → exact slot restore
- remove former regular Space while fullscreen → destination admission
- close/minimize during transition

### Pass

- authoritative ownership/readiness exists for each admitted bootstrap state; uncertain candidates are deferred
- rule evaluated once only when metadata is usable; fullscreen-on-create never runs for bootstrap discovery
- spawn window never receives a temporary tiled frame
- transition timers are bounded/cancelled
- fullscreen events do not duplicate/admit/reorder
- bar/desktop numbering behavior follows fullscreen invariants

## POC-006 — Cached chooser and cross-Space focus

### Decision

Retain `hs.chooser` UI while proving a zero-enumeration cached backend and restoration behavior.

### Matrix

- warm/cold chooser invocation with many managed windows
- fuzzy title/application queries
- observed `Cmd+1…9` visible-row selection
- stable row order after focus/title/layout/Space/availability changes
- append/remove after window create/destroy
- normal cross-Space, minimized, app-hidden, and native-fullscreen selection
- rapid successive selections, opposite targets, stale focus callbacks, and timeout/late completion

### Pass

- invocation p95 ≤ 100 ms
- no global AX enumeration/per-window icon lookup on show
- survivor row order remains stable
- selection reaches/restores the final intended window without layout readmission side effects
- a newer selection remains authoritative over stale intermediate focus callbacks

## POC-007 — macOS settings and read-only doctor

### Decision

Classify minimal required/recommended/unsupported settings and determine whether a reliable read-only doctor remains small.

### Matrix

A/B toggle where permitted:

- native menu-bar auto-hide
- automatic Space rearrangement
- separate Spaces
- native numbered shortcuts
- Reduce Motion
- Stage Manager
- native edge tiling
- switch-to-app-Space behavior

### Pass

- each requirement has observable rationale
- exact supported-build setting label/path is documented
- a detected value maps reliably to PASS/FAIL; otherwise report UNKNOWN
- doctor performs no mutation/restart/logout/TCC change

If reliable detection is not cheap, ship documentation only.

## POC-008 — Native boundary fallback (conditional)

Run only if POC-001/002/003/006 proves an intrinsic Hammerspoon failure.

Build the smallest Swift/Objective-C experiment for that one boundary using public AX/AppKit APIs where possible and an isolated private API only where unavoidable. Compare reliability, latency, permissions, build/signing cost, and maintenance surface. Do not infer that native code solves Space APIs or Accessibility application delays.

A wholesale native rewrite requires evidence that multiple critical Hammerspoon boundaries fail and that the native POC materially improves them.

## POC cleanup gate

Before merging a production replacement:

- result document committed
- POC branch/code removed unless retained diagnostic has an ongoing owner/use
- selected fact copied into architecture/performance/settings docs as appropriate
- rejected mechanism named so a future agent does not repeat it without new evidence
