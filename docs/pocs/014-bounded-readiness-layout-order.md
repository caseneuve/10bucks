# Bounded native readiness and retained layout order

## Status

**Verified narrow same-debug-guest acceptance**, 2026-10-11. Not cold isolation,
physical-host performance or general application reliability. Historical B
admission loss remains preserved; its exact early guard was not recorded.

## Decision and evidence

Initial creation/focus ownership queries can return unknown before later positive
native ownership. Instrumented unchanged-production session `c61fbdb5169c`
recorded this for A. A pure Host→Windows regression independently demonstrated
that creation plus focus probes both returning unknown could leave an eligible
window unmanaged indefinitely without another event (212 passing, 1 failing).
This supports bounded creation-readiness retries, not admitting from focus,
assuming active-Space ownership, permanent polling or pruning from absence.

The replacement in `lib/macos/window_host.lua` owns one ephemeral exact-candidate
creation/launch token: initial attempt plus at most two 100ms one-shot retries.
Unknown ownership/incomplete metadata/Rules defer may retry. Exclusion, identity
conflict or observer/sink rejection settles. Duplicate signals coalesce; genuine
creation upgrades launch origin without resetting budget. Focus/bootstrap do not
schedule retries. Provisional focus-handle release cannot cancel the independent
creation token. App/resource/context/generation cancellation, exception cleanup,
exact timer identity and final pre-publication authority are covered. No global
reacquisition, repeated app enumeration, permanent polling or adapter durable-state
mutation. Removed the former one-shot creation/launch path in the same replacement.

Independent high review exposed four additional failing-before cases (221 pass,
4 fail): stranded exception token, old timer consuming a newer attempt, resource
replacement during final native read, and creation-origin loss. All were repaired
and independently rechecked; final pure suite is 226 passing, zero failing.

## Environment and native procedure

Same exclusively owned running Tart guest, no reboot between diagnostics:
macOS 26.6.2 (25G83), Apple Silicon, Hammerspoon 1.1.1, SIP/AX enabled,
unlocked console, Secure Input off, one native 1024×768 logical display;
menu auto-hide on, MRU rearrangement off. Host legacy untouched.

```sh
./functional-tests/run --headed --reuse-debug VM_NAME columns-close-recovery
./functional-tests/run --headed --reuse-debug VM_NAME stack-columns-membership
```

Frozen AppKit fixture now accepts unique A–E aliases. Exact owned resources
provide global native focus, frames and authoritative close/AX-invalidity facts.
Cached candidate order/layout snapshots are secondary, never expected geometry.
Real hotkeys require exact callback-receipt increments. No fixture focus repair.
Thresholds unchanged: 5s/checkpoint, 250ms stability, 50ms sampling, maximum
150ms sample/delivery gap and 2 logical-point frame tolerance.

## Combined sequence

Start empty stack; create A/B/C; navigate C→B→A→B; switch columns retaining
B focus with left [A,B], right [C]; focus right/create D; switch stack integrating
D; create E; wrap E→A→E; background-close A; switch columns retaining left [B],
right [C,D] and integrating E into right; navigate E→C→E→D→E; focus left B;
close B, recovering source-side D into left [C,D]/right [E]; background-close E,
normalizing left [C]/right [D] while preserving D focus; close D, leaving C
full-width; switch stack with only C. Both modes create/close; ≥3-member navigation
can detect reversed ordering. Every boundary checks exact stable admission order,
retained assignments and active selection. Inactive columns B/D selections and
active right are explicitly checked before reactivation can conceal corruption.
Columns must be absent until first activation; no false preinitialization contract.

## Independently reviewed results

Ignored evidence under `vm/results/10bucks-run-ft-eaa07ef31097/`:

- `session-c64997e5d01e`: prior focus/close scenario PASS, 51 hashes,
  178 trace samples/139 assertion rows/23 checkpoints; minimum stability
  250.03ms; max acquisition13.55ms/start gap108.30ms.
- `session-d855e90e8e3e`: combined PASS, 51 hashes, 305 trace samples,
  250 assertion rows/40 checkpoints covering24actions; minimum stability250.17ms;
  max acquisition3.94ms/start gap109.06ms.
- Lead and independent high reviewer verify native geometry/focus/closure,
  receipts, stable order/both retained layouts and normal unforced cleanup.
- Combined B/C/D/E each had unknown ownership before confirmed second creation
  attempt; retry spacing102.87–103.79ms. They remain unmanaged while uncertain
  and admit after positive readiness. Nine total creation attempts/14 ownership
  reads, no alias exceeds3attempts. A used one creation attempt.
- Candidate/fixture/task/observers/controller timer stopped, normal quit ack,
  claims absent, pointer restored; debug VM deliberately retained running.
  Results correctly use cold `acceptance:false`.

These samples verify bounded recovery natively, not the exact cause of historical
`78f869c3c4ad`, exhaustion/third-attempt behavior, or performance-contract statistics.

## Harness corrections and checks

Combined initial import failure was pre-native (missing module Observation).
`7f8befedbbf2` failed before scenario actions because empty HS JSON tables encode
as []; normal cleanup observed. Adapter normalizes empty frame/receipt maps to
empty dictionaries. These failures remain retained; neither is platform evidence.
`--demo` is rejected for combined scenario: action pauses cannot fit the unchanged
55s guest watchdog. No threshold extension or weakened assertions.

20 Python oracle checks and226Lua pass; real guest11API gate passes, Swift fixture
build/Lua/Python/shell syntax/diff checks pass. Modeled negative coverage catches
reversed navigation, reordered/reset layouts, lost inactive assignments/selections,
stale closed members, incorrect native focus and geometry.

## Remaining / next

General real-app reliability, cold expanded-scenario acceptance, native fullscreen,
rapid pending commands and physical-host performance are unaccepted. No new bar
pixel claim from these runs. Next native slice: minimize/restore and overlapping
hide/minimize while retaining order in both layouts, using the same owned debug
guest and exact native observations. Failed manual real-app behavior still requires
its own regression; a fixture pass does not certify every application.
