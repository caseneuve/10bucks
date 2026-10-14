---
title: Status bar intermittently disappears and cannot be recovered
status: open
priority: high
type: bug
labels: []
created: 2026-10-14
parent: null
blocked-by: []
blocks: []
---

## Context

User session notes (updated 2026-10-14 10:55) report that the custom status bar
sometimes disappears and cannot be made visible again. The user reports this in
both legacy and rewrite versions. Trigger and attempted recovery actions are not
specified; do not invent a reproduction sequence or infer a common root cause.

**User-observed:** intermittent missing bar. **Hypothesis:** incorrect retained
visibility/fullscreen context, pointer handoff not ending, native canvas lifecycle,
or a visible-but-not-rendered overlay. No native trace or pixel capture settles it.

## Acceptance Criteria

- [ ] Capture a bounded failure trace separating requested presentation, native
      canvas state, actual pixels, regular/fullscreen context and pointer handoff.
      Use owned fixtures and sanitized aliases; identify a reproducible sequence.
- [ ] On regular desktops outside intentional menu-bar handoff, the bar is visibly
      rendered and returns after a legitimate hide condition ends.
- [ ] Fullscreen hiding and native menu-bar pointer access remain correct; no
      permanently hidden state after transitions or error/shutdown/restart paths.
- [ ] Verify rendered pixels independently: canvas isShowing or manager state alone
      is insufficient. Reuse recorded overlay-level evidence instead of assuming it.
- [ ] Add generic transition/failure coverage, targeted native visual acceptance
      and render/resource/service measurements. No permanent refresh poll or repeated
      forced redraw workaround without proved necessity and deliberate approval.

## Affected Files

- `10bucks.spoon/lib/bar.lua` — semantic bar presentation.
- `10bucks.spoon/lib/macos/bar.lua` — canvas lifetime, visibility and pointer handoff.
- `10bucks.spoon/lib/macos/context.lua`, `10bucks.spoon/init.lua` — context routing.
- `functional-tests/bar_capture.py`, `tests/test_bar.lua` — pixels and pure transitions.
- `docs/invariants.md` — BAR-001/002/006/007; recorded POC003/013 evidence.

## E2E Spec

GIVEN a visible bar on a regular desktop, WHEN the independently diagnosed
transition sequence temporarily hides it and returns to a regular desktop with
pointer handoff ended, THEN the bar's pixels reappear within the approved event
budget, native menu-bar access still works, and no extra permanent timers/resources
or corrective reload are required.

## Notes

Keep legacy occurrence as reported provenance, not proof of shared code/cause.
Do not add permanent production diagnostics or silently force host reloads.
User notes request tracking only; native reproduction later in the owned VM.
