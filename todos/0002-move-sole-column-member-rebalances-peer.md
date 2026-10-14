---
title: Moving a sole column member should rebalance from the destination column
status: done
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

- [x] Deliberately revise COL-006's reject-if-source-empty contract to the requested rebalance behavior; do not silently preserve the old rejection tests.
- [x] For `A,B | C` with left selection A and actual focus C, Hyper+O yields exactly `C,A | B`, with C focused/selected left and B selected right.
- [x] Select the last eligible non-selected destination member to refill the source; do not displace the destination's retained selected member.
- [x] Apply the same rule symmetrically when moving the sole left-column member right.
- [x] Never retain an empty durable column; explicitly define the result when no replacement exists (including only two total members).
- [x] Define replacement eligibility for minimized, hidden and native-fullscreen members using the existing independent availability contracts.
- [x] Managed-target authority uses actual managed focus; excluded/unknown actual focus still rejects.
- [x] Generic sequence tests and targeted real-hotkey/native-focus acceptance cover ordering, selection, availability and both directions.

## Affected Files

- `docs/invariants.md` — deliberate COL-006 revision.
- `10bucks.spoon/lib/layouts/columns.lua` — atomic move/rebalance and ordering.
- Existing generic columns/core/composition tests — replace old rejection contract where superseded.
- Functional column-movement scenario — real Hyper+O receipt and independent native focus/frames.

## E2E Spec

GIVEN two columns `A,B | C`, retained left selection A and actual managed focus C
WHEN the user presses Hyper+O
THEN membership/order becomes `C,A | B`, C remains actually focused/selected in the left column, B fills/is selected in the right column, and no intermediate empty-column or wrong-layout frame is requested.

## Delivery evidence

**Verified:** 334 Lua tests and 73 Python oracle tests pass; independent reviewer
found no production defect. Scoped reused-guest native run r7 passed all 25 actions
with real HyperO callback receipts, independent global native focus/frames, exact
ordered groups/selections, minimized replacement rejection, restore/rebalance,
successful sole-source moves in both directions and two-member rejection.

Artifacts: `vm/results/10bucks-run-ft-eaa07ef31097/session-2b84cad4bc45/`
(`manifest.json`, `guest-result.json`, `host-result.json`, `assertions.jsonl`).
Frozen reducer SHA-256: `d786e0795ce08f98c1bd6a8cff1f5e73addfbf825c1fd26e34c2c828f95bdeb4`.
Executed product/controller/scenario hashes matched checkout. 332 guest samples,
zero drops, no controller error; candidate/fixture stopped normally, native worker
drained, final fresh check found no ordinary windows. Persistent guest remains
running. Runner marks reused runs `acceptance:false` (not cold acceptance) while
`pass:true`/`scenarioPassed:true` establish this scoped functional result.

Earlier r1–r6 failures remain unchanged: incorrect oracle transitions/replacement
expectations and sampler startup/slow AX reads, not product/platform verdicts.
Lifecycle setup now uses the existing bounded settlement boundary before
checkpoint acquisition; no stability claim covers minimize/restore animation.
Hidden/fullscreen overlapping conditions and unknown-focus rejection are pure
regression coverage; unchanged actual-focus authority also inspected in source.
Existing configured-rules native excluded-focus rejection remains applicable;
it was not rerun for quota. No cold-start, pixel or performance claim. Review
reports remain in `.pi/bug0002-review*.md`.

**Host delivery / user acceptance:** implementation committed as `f42c953`.
User subsequently authorized host loading; frozen candidate
`.pi/host-candidates/move-f42c953-20261014T2205/` loaded alone after the previous
candidate stopped and its worker drained. Verified 26 enabled bindings, unchanged
configuration/rules and loaded columns source identity. User then confirmed
“great” and requested ticket closure. Status remains `done` (delivered), not
`closed` (abandoned/superseded).

## Notes

Implementation and subsequent host load authorized by the user on 2026-10-14; no further host actions implied by ticket closure. Approved defaults: prepend a moved sole member and preserve other destination order; choose the last available non-selected destination member; reject unchanged if no replacement exists, including only two members. Ordinary moves from a multi-member source still append. Availability uses independent minimized/app-hidden/native-fullscreen conditions. COL-006 deliberately revised before implementation. No app-specific policy. Read `.pi/WORK_STATE.md` for current frozen host and operational authority.
