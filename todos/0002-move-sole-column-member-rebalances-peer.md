---
title: Moving a sole column member should rebalance from the destination column
status: open
priority: high
type: bug
labels: []
created: 2026-10-13
parent: null
blocked-by: []
blocks: []
---

## Context

User reports columns `A,B | C`, with C actually focused: Hyper+O does nothing. Current COL-006 explicitly rejects moving a member when it would empty its source column. User requests a deliberate replacement of that rule: move the sole source member, and refill its source column from the last non-selected member of the destination column.

Concrete requested transition: left selection A, right selection/actual focus C:

```text
A,B | C  →  C,A | B
```

C remains actually focused and selected in the left column; A remains in the left column; B fills the right column. The requested order is `C,A`, not `A,C`.

## Acceptance Criteria

- [ ] Deliberately revise COL-006's reject-if-source-empty contract to the requested rebalance behavior; do not silently preserve the old rejection tests.
- [ ] For `A,B | C` with left selection A and actual focus C, Hyper+O yields exactly `C,A | B`, with C focused/selected left and B selected right.
- [ ] Select the last eligible non-selected destination member to refill the source; do not displace the destination's retained selected member.
- [ ] Apply the same rule symmetrically when moving the sole left-column member right.
- [ ] Never retain an empty durable column; explicitly define the result when no replacement exists (including only two total members).
- [ ] Define replacement eligibility for minimized, hidden and native-fullscreen members using the existing independent availability contracts.
- [ ] Managed-target authority uses actual managed focus; excluded/unknown actual focus still rejects.
- [ ] Generic sequence tests and targeted real-hotkey/native-focus acceptance cover ordering, selection, availability and both directions.

## Affected Files

- `docs/invariants.md` — deliberate COL-006 revision.
- `10bucks.spoon/lib/layouts/columns.lua` — atomic move/rebalance and ordering.
- Existing generic columns/core/composition tests — replace old rejection contract where superseded.
- Functional column-movement scenario — real Hyper+O receipt and independent native focus/frames.

## E2E Spec

GIVEN two columns `A,B | C`, retained left selection A and actual managed focus C
WHEN the user presses Hyper+O
THEN membership/order becomes `C,A | B`, C remains actually focused/selected in the left column, B fills/is selected in the right column, and no intermediate empty-column or wrong-layout frame is requested.

## Notes

Todo-only request: no implementation, host reload or window actions authorized by filing this item. User's example establishes the three-member transition; larger-stack placement, unavailable replacements and no-replacement behavior require explicit resolution before implementation. No app-specific policy. Read `.pi/WORK_STATE.md` for current frozen host and operational authority.
