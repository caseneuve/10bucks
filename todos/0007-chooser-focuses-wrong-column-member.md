---
title: Chooser reaches target desktop but focuses a different column member
status: blocked
priority: high
type: bug
labels: []
created: 2026-10-14
parent: null
blocked-by: []
blocks: []
---

## Context

User session notes (updated 2026-10-14 10:55) reiterate a chooser bug: selecting
Thunderbird reaches its desktop but focuses a different window in the **same column**.
The selected target and wrong peer's exact resources, event order and persistence
have not been captured. Thunderbird is reproduction context, not engine policy.

This is distinct from TODO0004's explicit fullscreen rejection and TODO0001's
close recovery. Their focus-authority seams may be relevant, but a shared cause is
unproved. The previously accepted cross-Space fixture had a single destination
member and therefore did not cover this same-column competition.

**Hypothesis:** destination retained selection/native fallback or Space activation
reflow supersedes the explicit chooser target, or the wrong focus observation
confirms it. Do not assume stale native ID or any specific callback race as fact.

## Acceptance Criteria

- [ ] Reproduce cross-Space selection with at least two available managed members
      in the destination column and a different retained selection before the command.
      Capture selected row, exact resource, request/Space/focus event order and native
      final focus independently; distinguish a transient fallback from final failure.
- [ ] The selected chooser target becomes the confirmed native focused window,
      even when its same-column peer was previously selected or receives fallback focus.
- [ ] Validate exact current resource/ownership; commit desired selection before
      effects. Space activation/stale callbacks must not overwrite a newer explicit
      chooser target or falsely clear its pending request.
- [ ] Preserve surviving group/admission order and other columns' selections;
      unmanaged focus does not admit or rewrite managed history.
- [ ] Cover same-Space, cross-regular-Space, unchanged target, superseding requests,
      destroyed/replaced resources and delayed/failed confirmation generically.
- [ ] Native acceptance uses real chooser keyboard selection and asserts exact
      final native focus/Space with unchanged stability/freshness gates—no corrective
      focus to repair a failing checkpoint. Measure focus and concurrent key service.

## Affected Files

- `10bucks.spoon/init.lua` — chooser/shared focus requests and Space activation routing.
- `10bucks.spoon/lib/core.lua`, `10bucks.spoon/lib/model.lua` — desired/actual authority.
- `10bucks.spoon/lib/focus_history.lua` — global pending/confirmation semantics.
- `10bucks.spoon/lib/macos/window_host.lua` — exact native focus/read observation.
- `functional-tests/scenarios/`, `tests/` — destination competing-column sequence.
- `docs/invariants.md` — FOCUS-003/006, CHOOSE-004, CMD-005 and STATE-002.

## E2E Spec

GIVEN source-desktop S and destination T with same-column managed members A/B,
retained selection B, and chooser target A, WHEN a real chooser selection requests
A from S and T activates, THEN native focus settles on exact A, matching confirmation
clears A's pending request, B does not supersede it through fallback/activation,
and column order is unchanged. Repeat with a later explicit target superseding A.

## 2026-11-24 triage
On hold for observation: the user thinks this has already been addressed. No
specific fix or same-column native acceptance has been verified for this report.
Resume if it recurs.

## Notes

Reuse POC009 focus confirmation and POC021/022/023 chooser/Space evidence, but do not
claim single-member destination acceptance proves this sequence. Cross-reference
TODO0001 for recovery authority and TODO0004 for fullscreen selection only; keep
separate outcomes/contracts and no app-specific source branches or wrapper stacks.
User reports this as already raised; no existing dedicated regular-chooser wrong-
member TODO was found, so this item preserves the repeated report without merging
it into close recovery. Tracking only: no runtime fix, host effects or priority
change is implied by the notes.
