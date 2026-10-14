---
title: Focus already-managed native-fullscreen windows from chooser
status: open
priority: high
type: feature
labels: []
created: 2026-10-14
parent: null
blocked-by: []
blocks: []
---

## Context

User manual testing of `77abbcf` reports that visiting a native-fullscreen window
makes it appear in the chooser, but selecting it does not focus it. The chooser
exposes the internal rejection reason `chooser-restoration-deferred`.

Verified source: `init.lua:_chooseWindow()` rejects unavailable or unplaced targets
before using the existing managed-target focus path. Listing is implemented;
selection of this known target is not. Deferring **cold-start discovery** of
fullscreen/minimized windows did not mean this known-window selection was useful.

Deliver this narrow part of roadmap step 5: focus an already-confirmed managed
native-fullscreen window in its existing fullscreen Space. Do not conflate this
with toggling fullscreen, discovering unknown windows, or restoring hidden/minimized
windows. If either of those independent flags also applies, keep the boundary
explicit rather than silently implementing other restoration effects.

## Acceptance Criteria

- [ ] Selecting an already-managed, non-hidden, non-minimized native-fullscreen
      row reaches its current fullscreen Space and confirms exact native focus.
      Cover both retained regular placement and independently admitted unplaced
      fullscreen targets; never invent a regular layout slot for the latter.
- [ ] Revalidate the returned exact resource lease and current ownership before
      effects. Reject destroyed, replaced or uncertain targets without aliasing a
      reused native ID, broad enumeration or focus-driven admission.
- [ ] Commit the managed focus request before native effects; actual focus confirms
      it through the shared observation path. Latest chooser target wins; stale
      callbacks cannot overwrite a newer selection or focus-history authority.
- [ ] Preserve fullscreen mode, saved placement, layout grouping/order, chooser
      admission order and rules. Do not request tiled frames behind fullscreen.
- [ ] Respect existing pending desktop-creation/switch restrictions and shutdown
      cancellation. Failed/unconfirmed focus must not be reported as successful
      completion or strand pending authority.
- [ ] Successful selection does not show `chooser-restoration-deferred`. Any genuine
      rejection/failure uses actionable user-facing wording, not internal codes.
- [ ] Add generic pure sequence/resource/effect-budget coverage and targeted native
      UI acceptance, then relevant focus/key-service measurements and independent
      raw/source/simplicity review. Reuse proved mechanisms; preserve failures and
      verify candidate/observer/worker/fixture cleanup.

## Affected Files

- `10bucks.spoon/init.lua` — chooser target validation and existing shared managed
  focus path; avoid a parallel fullscreen selection implementation.
- `10bucks.spoon/lib/macos/chooser.lua` — user-facing selection failure feedback.
- `10bucks.spoon/lib/focus_history.lua` — existing placed/unplaced ownership and
  pending-confirmation behavior, only if a demonstrated gap requires a change.
- `10bucks.spoon/lib/macos/window_host.lua` — existing exact-handle focus/observation
  port; native Space adapter only if current focus mechanisms prove insufficient.
- `tests/`, `functional-tests/` — generic native-fullscreen fixtures, actual visible
  row selection, exact native focus/Space outcomes and separate measurements.
- `docs/development-roadmap.md`, `docs/pocs/` — truthful scoped restoration delivery
  and remaining deferrals, not edits that reinterpret historical acceptance.

## E2E Spec

GIVEN a managed regular window A and a separately confirmed managed native-fullscreen
window F, with F neither app-hidden nor minimized and currently listed in the chooser,
WHEN the chooser is opened on A's regular desktop and F is selected using real
keyboard input,
THEN the active native Space becomes F's existing fullscreen Space, native focus
matches F's exact resource, the pending request clears on confirmation, and F remains
fullscreen with its saved placement/order unchanged.

Repeat with an independently admitted unplaced fullscreen target, unchanged-target
selection, and a newer chooser target superseding an unconfirmed request. Negative
cases must detect stale resource replacement, destruction, uncertain ownership,
blocked structural operations and failed confirmation without corrective focus.

## Notes

- Separate from `0003-chooser-global-unavailable-window-discovery.md`: this task starts
  with known, independently confirmed membership. No cold-start completeness work,
  brute-force expansion, global chooser-time scan or permanent polling.
- Unminimize/unhide, overlapping lifecycle restoration, native-fullscreen toggle and
  fullscreen-on-create remain separate delivery slices. Do not weaken their flags.
- Relevant contracts: CHOOSE-001/002/003/004, FOCUS-003/005/006, FS-002/005,
  STATE-001/002/003/007 and CMD-005/006.
- Reuse `docs/pocs/009-focus-confirmation.md` and
  `010-fullscreen-focus-history.md` for narrow focus/ownership evidence;
  POC021/022/023 record the existing UI, exact-resource and lifecycle boundaries.
  Their unavailable-selection tests currently prove rejection, not fullscreen-focus
  success. Replace that slice's obsolete rejection expectation deliberately while
  retaining separate minimized/hidden rejection coverage.
- Keep one runtime path and existing membership/resource/focus owners. No new cache,
  registry, queue, epoch, speculative wrapper framework or app-specific policy.
- User requested TODO only in this turn. No runtime change, host reload, window/Space
  action or priority change over bugs0001/0002 is implied. Native testing uses the
  coordinator-owned VM; any later host load needs explicit authority.
