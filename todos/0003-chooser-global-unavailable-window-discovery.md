---
title: Investigate deferred fullscreen and minimized chooser discovery
status: open
priority: medium
type: feature
labels: []
created: 2026-10-14
parent: null
blocked-by: []
blocks: []
---

## Context

**Deferred by user decision, 2026-10-14:** fullscreen and minimized cold-start
discovery need further investigation rather than speculative machinery. Ordinary
regular-desktop discovery remains an active MVP correction; treating it as deferred
was a coordinator scope error, corrected by the user. After investigating uncertain
native surfaces, the user explicitly accepted a bounded best-effort startup attempt
with confirmed rows usable and no discovery warnings/blocking in the chooser.
Do not confuse discovery with the separately scheduled restoration/focus effects.
Already discovered unavailable members remain retained in the existing cache.

The user reported that cold start lists only current-desktop windows, and proposed
subtracting the AX-exposed IDs from a complete native-window inventory to identify
missing candidates. That set difference is deterministic given a complete inventory;
obtaining an exact AX resource and confirming management eligibility is a separate
problem. Best-effort startup does not promise completeness: unresolved candidates remain
unknown. Ordinary regular-desktop discovery is an active correction, not part of this
deferral; its native mechanism and cold-start behavior must be proved before delivery.

## Acceptance Criteria

- [ ] Record a concrete supported-build investigation procedure before effects;
      distinguish verified facts from hypotheses and preserve failed probes.
- [ ] Test a genuinely all-window inventory, not only onscreen surfaces; establish
      scope, native identity/PID/Space joins, exclusions and unavailable-window limits.
- [ ] Compare inventory IDs with existing AX/managed identities to report unresolved
      targets; do not treat inventory absence as destruction or IDs as AX resources.
- [ ] Establish whether inactive regular, pre-existing fullscreen and minimized
      windows can be resolved completely within measured startup/service budgets.
      Explicitly document ambiguity and any remaining incompleteness.
- [ ] Independently review private-API resource ownership, cancellation, cleanup and
      failure evidence before selecting a production mechanism. If complete discovery
      is not achievable, obtain a deliberate contract decision instead of silently
      switching to best effort.
- [ ] Before implementation, agree the discovery scope and selection/restoration
      boundary, revise canonical contracts deliberately, and split delivery work
      into narrow tasks if the investigation reveals multiple substantial changes.

## Affected Files

- `10bucks.spoon/lib/macos/window_host.lua` — startup discovery and native readiness.
- `10bucks.spoon/lib/macos/handle_registry.lua` — existing exact-resource ownership;
  preserve its authority, not a second registry.
- `10bucks.spoon/lib/window_chooser.lua`, `10bucks.spoon/init.lua` — managed-only cached
  projection and existing placed/unplaced state routing.
- `docs/invariants.md`, `docs/architecture.md`, `docs/pocs/` — explicit contracts and
  recorded mechanism evidence, not retrospective edits to historical results.
- `tests/`, `functional-tests/` — generic identity/scope/uncertainty sequences and
  independently observed native outcomes; separate benchmarks and stress.

## E2E Spec

GIVEN a fresh candidate with ordinary managed windows on active and inactive regular
Spaces, independently eligible fullscreen/minimized windows, and generic excluded
windows, with the discovery scope deliberately approved,
WHEN startup discovery completes and the chooser is opened without first visiting
those Spaces,
THEN every confirmed managed target in that scope is listed exactly once, excluded
windows are absent, unresolved candidates are not falsely represented as confirmed,
opening performs no global enumeration, and discovery has not switched Spaces or
requested focus. Selection obeys the separately approved restoration boundary.

## Notes

### Verified evidence as of 2026-10-14

- Installed Hammerspoon 1.1.1 `application:allWindows()` documents current Mission
  Control Space scope. An owned-VM fixture with active A, inactive regular B and
  native-fullscreen C exposed only A through `allWindows`, `AXWindows`, `AXChildren`
  and navigation children. Known B/C `hs.window.get` lookups returned nil.
- Hammerspoon `hs.window.list(true)` still uses `kCGWindowListOptionOnScreenOnly`;
  `true` changes Dock filtering, not cross-Space completeness. Therefore its one-row
  result does **not** disprove a raw `kCGWindowListOptionAll` inventory.
- Changing the owned fixture's `AXEnhancedUserInterface` did not expose B/C; original
  value was restored. A private move operation reported acceptance without confirmed
  movement; that setup was discarded and B was created on its actual destination.
- A disposable private `_AXUIElementCreateWithRemoteToken` probe recovered exact
  B/C AX resources: `AXWindow` role, native identity/PID, equality with independently
  held AX resources, `asHSWindow` equality and confirmed owners. Current Space and
  focus matched before/after. This proves **reachability**, not complete discovery.
- Fixed probe attempted 3,650 AX element IDs within a 100ms starting-query budget
  (100.039ms observed), with 3,647 lookup errors. AX element IDs are not WindowServer
  window IDs. Finite ranges/time budgets leave sparse and lifetime-growing IDs
  unresolved; lookup errors are not destruction evidence. That initial probe added
  no production helper or repeated scan. The later bounded regular-desktop helper
  is recorded in POC023; it does not prove deferred unavailable-window completeness.
- Minimized-window cold-start resolution was **not** separately proved by this probe.
  Fullscreen selection/restoration remains distinct from merely listing a target.

### Hypotheses / remaining investigation

- A later owned-fixture raw `CGWindowListCopyWindowInfo(kCGWindowListOptionAll)`
  probe included both active/inactive ordinary windows at about0.8ms. Intersecting
  with regular-Space memberships excluded four extra fixture surfaces. This is
  narrow fixture evidence, not universal completeness or fullscreen/minimized proof.
- Even complete inventory does not establish a bounded, complete mapping from native
  window IDs to AX resources. An inventory-minus-AX set is a discovery worklist, not
  management/liveness proof. Investigate a direct mapping before adopting token scans.
- Source references and fixture results are not proof for every application. Do not
  introduce app-specific production conditionals, `hs.window.filter` fallback, startup
  Space visitation, polling or new queues/epochs to conceal uncertain discovery.

### Local operational evidence (ignored, checkout-specific)

- `.pi/handoffs/2026-10-14-chooser-corrections-blocked.md`
- `.pi/chooser-corrections-review.md`
- `.pi/poc/chooser-global-20261014/result.md` and frozen procedures/source references.
- `vm/results/10bucks-run-ft-eaa07ef31097/chooser-global-poc-20261014/` contains the
  13-artifact fixture/driver manifest, 3-artifact token source/binary manifest and raw
  results. Independent review verified 16 hashes, but records limitations: comparison
  driver outside token manifest and no independent loaded-binary identity proof.

Cleanup was verified: normal fixture quit/ack/exit, no mailbox claims, no ordinary
fixture windows, original three regular desktops/D1. Host frozen chooser stayed
unchanged during these probes. Do not repeat brute-force expansion ceremonially;
continue with deferred fullscreen/minimized resource resolution and completeness,
using the recorded regular-desktop inventory findings. No bug0001/0002 fix belongs
in this task.
