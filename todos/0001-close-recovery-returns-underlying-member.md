---
title: Close recovery returns an underlying member instead of the originating focused window
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

User manual test of ordered exclusions succeeded, but revealed a focus-recovery issue. In columns `A,B | C`, A is focused; A opens a managed secondary window D and an excluded transient E. After sending and closing D, focus lands on another underlying window rather than A. The exact observed destination (B in the same column versus C in the other column) was not confirmed.

**Verified:** pure generic columns sequence `A,B | C` → focus A → admit D gives `A,B,D | C`; removal plus source recovery chooses B. Current COL-005/FOCUS-004 specifies the last surviving available source-column member, not previous focused A. The expected return-to-A semantics need a deliberate contract decision; do not silently rewrite the invariant.

**Hypothesis:** fallback managed focus before authoritative D destruction can replace the source selection and suppress recovery. Excluded E leaves managed selection/history unchanged, but a later managed fallback can change them. No host event trace establishes this ordering yet.

## Acceptance Criteria

- [x] Generic normal case observes B before fix; user approved prior confirmed focused source survivor A.
- [x] COL-005/FOCUS-004 explicitly revised; no opener/app-specific policy.
- [x] Generic excluded-focus recovery and existing removal-first/pending-fallback coverage. Actual unknown-validity fallback-before-destruction remains a separate retained adapter limitation, not claimed fixed.
- [x] Deliberate B/C focus followed by background D closure preserves focus.
- [x] Stable membership/navigation order and unrelated column selection preserved.
- [x] Targeted native acceptance confirms exact A focus; controls confirm B/C.

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

**Decision resolved:** user chose option2, prior confirmed focused source survivor A,
and explicitly rejected B. No repeat A-vs-B investigation is required.

## Host feedback — reopened 2026-10-14

User reports loaded bb21137 does not fix the real sequence: A/B|C, actual A,
spawning new terminal first focuses existing B, then creates D. A is Thunderbird;
B/D are Ghostty. App names are reproduction context, not policy. Spawn gesture,
native/manager cause and exact event order are not yet traced. Intermediate B focus
can become the newest source history entry; fixture's direct D creation did not
cover activation of another app's existing window before creation. Do not suppress
legitimate focus or invent opener authority. User's desired recovery remains A;
no repeat preference question. Prior implementation/native fixture success is scoped,
not completed real-workflow acceptance. No new host effects authorized by report.

## User acceptance — 2026-10-14

User confirms the corrected HyperReturn launcher and loaded source-recency recovery
work in the actual workflow: “excellent, works”. BUG0001 closed. Productbb21137,
launcher correction recorded27ca064; no further native actions performed for closure.

## Launcher correction — 2026-10-14

Verified host skhd HyperReturn explicitly activated Ghostty before clicking New
Window, allowing existing B focus to precede D. User authorized direct creation.
Host HyperReturn now uses `osascript -e 'tell application "Ghostty" to new window'`;
only that line changed, backup retained privately. Existing skhd process received
its documented SIGUSR1 reload (CLI reload failed because pidfile was stale).

Narrow owned-guest Ghostty1.3.1 native probe: actual generic A with existing B →
direct command → one new D, final native D stable250ms,22samples/no observed B,
max sampled gap118ms,script exit0. Initial setup/permission-interrupted runs remain
unaccepted; Automation allowed through normal guest UI. Observer/timer stopped,
normal fixture quit acknowledgment/exit,Ghostty exit and0ordinary windows verified.
This is sampled launcher evidence, not proof of every transient or user-host
acceptance. No host shortcut/window action automated; user should verify A→D→closeA.
No engine app-specific exception or focus suppression introduced.

## Scoped fix checkpoint — 2026-10-14

Stack/Columns `RecoverSource` now consult the existing reducer-owned focus history,
filtered to available surviving members of the physical source. No new state,
native calls, worker changes, opener registry or admission snapshot. Stable `j/k`
order remains unchanged. Existing shared recovery also applies to minimize;
vanished sources retain structural normalization and history-less stable fallback.

Failing-before generic A/B/C/D/excluded regression now passes in both layouts;
unavailable prior member and background B/C controls covered.330Lua/71Python PASS.
Frozen VM normal4c99b6eb481b and excludedc5a729943906 confirm native A; deliberate
Cfdb0984a428f and B224115f63ea2 preserve C/B without recovery requests. All4 PASS,
396artifact hashes verified,0ordering drops,normal quit/wrapper cleanup and both
workers drained. Fresh postcheck0ordinary windows/firstdesktop/FTidle. Source review
GO; independent normal/C raw review confirms exact outcomes, strict joins,
no corrective focus, unchanged whole batches and normal worker drain.

No fresh benchmark population: pure policy change reuses unchanged native effects
and existing query path; no performance-certification claim. No host deployment:
frozen host77abbcf is unchanged and needs explicit load authority. Original
investigation FAILs remain preserved. The unobserved fallback-first/unknown-validity
adapter limitation is not repaired by this source-preference change.

## Notes

Deferred from the current rules story by explicit user decision: finish/commit rules and separate the test harness first, then fix found bugs. Do not initiate mail or put user-specific exclusion policy in the repository. Host frozen candidate/user config remains a separate boundary. Read `.pi/WORK_STATE.md` for runtime authority; ignored close-bug handoff supplies operational context. Historical initial review stalled, was cancelled, and queued input was cleared without a verdict. Independent source/native investigation review completed on 2026-10-14; the policy decision is resolved and the source-preference correction is implemented, but user host feedback reopens the actual workflow as recorded above.
