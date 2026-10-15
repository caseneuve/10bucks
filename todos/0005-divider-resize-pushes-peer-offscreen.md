---
title: Divider resizing pushes a peer window beyond the screen
status: done
priority: high
type: bug
labels: []
created: 2026-10-14
parent: null
blocked-by: []
blocks: []
---

## Context and approved scope

User reported repeated Hyper+[ / Hyper+] resizing pushing a peer offscreen with
Herdr inside Ghostty and Chrome. Native minimum width, AX write order and
requested-versus-observed frame mismatch were hypotheses, not established causes.
These app names are reproduction context, not engine policy.

On 2026-10-15, after appearance work and with columnGap=8, the user confirmed four
5-percentage-point steps from 50/50 work; the fifth pushes Chrome slightly offscreen.
The user approved the smallest mitigation: symmetrically cap the divider at
30–70%, removing the final expansion step in either direction.

This replaces the original broader acceptance scope (generic constrained-size
fixture, adaptive constraint/fallback policy and native query-budget measurements).
Those investigations were not executed and are not required for this delivered
fixed-cap mitigation. Native minimum-size enforcement and universal containment
remain out of scope; smaller displays, larger gaps or other windows can still
require more width than the fixed limit permits.

## Acceptance Criteria

- [x] Production divider bounds are 0.30–0.70; further outward commands leave the
      ratio at the bound, using the existing reducer without app exceptions.
- [x] Existing composed ratio/retention test covers repeated presses in both
      directions; existing ratio tests cover deltas/reset. Lua suite: 350 pass,
      0 fail; diff whitespace clean.
- [x] No membership, selection, focus or native frame-write path changes; no new
      corrective effects, polling or constraint machinery.
- [x] Load frozen candidate on authorized host preserving gap8 and appearance.
      User responded “cool” and requested completion after load. This is
      user-reported acceptance, not independently captured native containment proof.

## Delivered files

- `10bucks.spoon/init.lua` — composition bounds changed from 0.25–0.75 to 0.30–0.70.
- `tests/test_composition.lua` — five lines added to existing COL-008 coverage.
- `docs/invariants.md` — approved fixed-limit policy and limitations in COL-008.

## Host result

Frozen candidate: `.pi/host-candidates/divider-cap-20261015T114048Z/`.
Verified 33 frozen artifacts; only runtime `init.lua` differs from the accepted
visual candidate. Loader verified previous worker drain and successful replacement.
Fresh IPC confirmed sole candidate running, bounds 0.30/0.70, gap8, 26 enabled
bindings, two rules and chooser `;`; discovery pending=false (not a completeness
claim). Host config/legacy entrypoints unchanged. No synthetic test keys or Space
actions were performed.

## E2E expectation

GIVEN the user's confirmed current setup, WHEN resizing outward from reset,
THEN four steps are allowed and the fifth leaves the divider unchanged; reversal
and reset retain their existing behavior. Completion is deliberately limited to
this fixed-cap mitigation, not an adaptive native-size solution.
