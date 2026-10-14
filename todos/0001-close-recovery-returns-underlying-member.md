---
title: Close recovery returns an underlying member instead of the originating focused window
status: blocked
priority: high
type: bug
labels: []
created: 2026-10-13
parent: null
blocked-by: []
blocks: []
---

## Context

User manual test of ordered exclusions succeeded, but revealed a focus-recovery issue. In columns `A,B | C`, A is focused; A opens a managed secondary window D and an excluded transient E. After sending and closing D, focus lands on another underlying window rather than A. The exact observed destination (B in the same column versus C in the other column) was not confirmed.

**Verified:** pure generic columns sequence `A,B | C` → focus A → admit D gives `A,B,D | C`; removal plus source recovery chooses B. Current COL-005/FOCUS-004 specifies the last surviving available source-column member, not previous focused A. The expected return-to-A semantics need a deliberate contract decision; do not silently rewrite the invariant.

**Hypothesis:** fallback managed focus before authoritative D destruction can replace the source selection and suppress recovery. Excluded E leaves managed selection/history unchanged, but a later managed fallback can change them. No host event trace establishes this ordering yet.

## Acceptance Criteria

- [ ] Confirm observed destination and approved generic close-recovery target (prior focused source member versus last admitted survivor).
- [ ] Deliberately update contracts if needed; no app-origin or app-specific production exception.
- [ ] Reproduce with generic windows and cover excluded focus plus fallback-before-destruction ordering.
- [ ] Deliberate user focus followed by background closure preserves that focus; no recovery stealing.
- [ ] Preserve stable membership/group order and unrelated column selection.
- [ ] Targeted native acceptance confirms actual focus, not desired selection alone.

## Affected Files

- `10bucks.spoon/lib/core.lua` — recovery authority before removal/fallback focus.
- `10bucks.spoon/lib/layouts/columns.lua` — source-column recovery selection.
- `10bucks.spoon/lib/macos/window_host.lua` — exact destruction/invalidity before fallback observations, if proved relevant.
- `docs/invariants.md` — only after explicit recovery-contract decision.
- Existing generic sequence tests and native functional scenarios.

## E2E Spec

GIVEN columns `A,B | C`, A focused, managed D opened into A's column, and excluded E temporarily focused
WHEN E disappears and D closes normally
THEN actual focus returns to the explicitly approved source-column target, with stable surviving order and no excluded membership/history/effects.

ALSO GIVEN a deliberate user focus on another managed window before a background D close
THEN closure does not steal focus.

## Investigation checkpoint — 2026-10-14

[Generic native investigation](../docs/bug0001-close-recovery-investigation.md)
reproduces current-contract B after E/D close; deliberate B/C focus followed by
background D closure preserves that focus. No close-phase C fallback was observed
in the normal case. Excluded E leaves managed history/effects unchanged. Four
frozen cases independently reviewed,395artifact hashes,327Lua/71Python checks;
two original evidence-validator FAILs retained with separately reviewed re-analysis.
No product fix or benchmark acceptance. Owned VM cleanup verified; host unchanged.

**Blocked on deliberate generic recovery-policy decision:** last available source
survivor B versus previously confirmed focused source member A, and recency/snapshot,
unavailable/source-collapse and minimize/movement scope. Do not silently revise
COL-005/FOCUS-004 or start another bug while this is unresolved.

## Notes

Deferred from the current rules story by explicit user decision: finish/commit rules and separate the test harness first, then fix found bugs. Do not initiate mail or put user-specific exclusion policy in the repository. Host frozen candidate/user config remains a separate boundary. Read `.pi/WORK_STATE.md` for runtime authority; ignored close-bug handoff supplies operational context. Historical initial review stalled, was cancelled, and queued input was cleared without a verdict. Independent source/native investigation review completed on 2026-10-14; the policy decision and product fix remain blocked.
