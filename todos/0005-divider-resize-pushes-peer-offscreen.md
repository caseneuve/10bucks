---
title: Divider resizing pushes a peer window beyond the screen
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

User session notes (updated 2026-10-14 10:55) report that repeated Hyper+[ / Hyper+]
resizing grows one column while its peer stops shrinking and is pushed beyond the
screen edge, leaving content invisible. Reported pairing: Herdr inside Ghostty
and Chrome; Chrome stopped shrinking when the other column occupied roughly two
thirds of the display. These app names are reproduction context, not engine policy.

**User-observed:** offscreen peer after divider changes. **Hypothesis:** a native
minimum-width constraint, AX size/position application order, or requested-versus-
observed frame mismatch. No trace proves any of these causes or an exact threshold.

## Acceptance Criteria

- [ ] Reproduce with generic resizable windows, including a fixture enforcing a
      minimum width; capture intended frames, actual native frames and write order.
- [ ] Deliberately define behavior when requested column widths cannot fit native
      minimum sizes. Do not silently revise layout geometry or introduce app rules.
- [ ] Successful divider changes keep supported windows fully within the usable
      display bounds, in both directions and after returning from an extreme ratio.
      If a constraint makes this impossible, use the explicitly approved fallback.
- [ ] Preserve grouping, admission order, selections and actual focus; no corrective
      focus or repeated frame-write/polling loop used to conceal geometry failures.
- [ ] Generic sequence tests and native constrained-size acceptance verify observed
      containment, not just projector output; measure relevant frame/query budgets.

## Affected Files

- `10bucks.spoon/lib/layouts/columns.lua` — bounded divider and frame intents.
- `10bucks.spoon/lib/geometry.lua` — usable-display geometry.
- `10bucks.spoon/lib/macos/window_host.lua` — native frame application/observation.
- `docs/invariants.md` — COL-008/STACK-001/CMD-003 and any deliberate constraint policy.
- `tests/`, `functional-tests/` — generic minimum-size fixture and native outcomes.

## E2E Spec

GIVEN two regular-desktop columns with a peer window enforcing a known minimum
width, WHEN repeated real divider shortcuts expand the opposite column through the
reported region and then reverse direction, THEN native window bounds follow the
approved constrained-size behavior without partially disappearing beyond the screen,
and focus/group order remain unchanged.

## Notes

Record the supported environment, ratio sequence and native sizes before effects.
Do not assume 2/3 is a universal threshold or add Chrome/Ghostty conditionals.
This is separate from TODO0002's column-membership movement bug. User notes request
tracking, not implementation or host mutation; coordinator-owned VM testing later.
