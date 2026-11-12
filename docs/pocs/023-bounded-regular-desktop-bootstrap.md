# Bounded regular-desktop bootstrap — best-effort correction

## Scope and status

**User-approved behavior:** one bounded cold-start attempt discovers ordinary
managed windows across regular desktops without activating them or requesting
focus. Confirmed rows remain usable during pending/incomplete discovery; no chooser
warning or opening block. Unresolved candidates stay unknown, not excluded/dead or
falsely reported as complete. Desktop visits and lifecycle events continue discovery.
Fullscreen/minimized cold-start discovery remains TODO0003; no restoration effects.

The previous ranking checkpoint did not satisfy this startup requirement. Its
already-discovered-only scope interpretation was rejected and corrected. The first
strict completeness attempts failed; this result applies to the later explicitly
approved best-effort contract, not a retrospective repair.

**Verified:** scoped cold-start and full chooser functional acceptance, settled
opening benchmarks and off-main discovery-job service. **Failed:** inclusive fresh
initialization service probe. Cold initialization responsiveness is not certified.
No physical-host/app-matrix/full-release claim or guarantee of resolving every
pre-existing window. Host readiness remains a separately authorized load operation.

## Responsibility-driven replacement

One Host-owned startup operation takes a public CG all-window inventory and regular
Space membership hints, enumerates application AX windows once, and sends missing
candidates to one native serial job. Native window IDs are discovery hints; each
accepted resource requires exact AX root/PID/window identity, confirmed ownership
and existing generic policy/readiness. No app-specific conditions, second registry,
streaming mailbox, resumable scan queue or epoch. Existing Core/unplaced state,
HandleRegistry, row reducer, ranking and focus effect owners remain unchanged.

The native one-shot worker uses the recorded private AX-token reconstruction seam,
retaining only exact AXWindow roots. Fixed scan range1..4096, per-PID100ms and
aggregate500ms starting-query budgets, messaging timeout1ms, cancellation checks,
terminal resource transfer and separately observable drain. Public image pinning
protects queued/in-flight code. These are bounded attempts, not hard IPC wall-time
or completeness guarantees. Normal-level targets are scheduled first, then stable
PID/native-ID order; this is scheduling, not an eligibility filter.

Exposed and reconstructed resources share bootstrap readiness. Confirmed exclusions
settle through the existing policy result; uncertain/rejected identity/ownership
cannot become complete. One post-admission actual-focus read observes, never focuses.
Stop cancels the bounded timer/job; stale factory/completion callbacks cannot replace
new authority. Pure tests cover failures, reentry, identity, cancellation, scheduling
and usable cached rows while startup is pending/incomplete.

## Platform evidence and limitations

Owned persistent SIP-enabled guest, macOS26.6.2/25G83, Apple Silicon, HS1.1.1,
Accessibility enabled, one1024x768 logical display, original3 regular desktops/D1.
Coordinator sole native operator; immutable candidate/native/fixture/helper artifacts.

Raw CG optionAll inventory included active A and inactive B in0.803ms. Regular-Space
intersection removed four extra fixture surfaces, but did not remove all system
surfaces globally. HS window.list(true) is onscreen-only; it cannot substitute.

Exact asynchronous inactive-B POC:7 frozen artifacts, exact AX/HS-window/PID/native
identity and D2 ownership,2.151ms/43 attempted AX IDs, unchanged source/focus.
Deterministic pre-publication cancellation suppresses resources and drains. A100-event
service population had p953.751/max30.518ms, but its two not-drained callbacks lacked
actual scan-start attribution. That limitation is preserved; later changed-runtime
measurement below closes actual overlap. POC hold controls were not shipped.

## Cold-start functional acceptance

`session-171c6984d9b4`:94/94 hashes,51 samples,40 assertion joins. Fixture A/D1 and
B/D2 exist and are independently joined **before candidate startup**. Native A focus
and D1 are proved; startup manager focus-request count remains0. First chooser
contains exact A/B before any observed post-start D2 visit. Native visible-row
selection chooses B and confirms B/D2 with pending clear; D2 reopen/cancel retains
cached rows. Attempt settled with complete=false/unresolvedCount20, honestly recorded.
No chooser warnings/blocking. Normal fixture/UI/binding/resource cleanup and worker
drain. Sampled Space history is not proof against every possible transient visit;
source contains no startup Space effect.

`session-213a9ee06d97`: full ranked chooser regression passes with the new startup
path, including real query/visible-row selection, title updates, exclusion, order,
regular cross-Space focus, unavailable rejection, closure and open-UI cleanup.
Independent frozen predicate replay and artifact checks passed. Existing POC021
setup-animation and inactive-unhide geometry qualifications remain.

## Separate settled opening measurements

Warm `97ef4faa6d55`, `945be5a13d7e`, `1a005a876779`; cold `c96d08b0a2c4`,
`dd7de9318fdb`, `f9b3bc79ce0a`, `2243be7236c5`, `c25f9712cfc9`.
496 verified hashes /62 artifacts each,30 measured warm+3 labeled warmups/5 fresh
candidate cold samples. Executed chooser/candidate bytes match; two unused startup
probe files changed between snapshots. Startup terminal status/time is recorded
before measurement, without requiring complete resolution.

| ms: median / p95 / maximum | Warm30 | Cold5 |
|---|---|---|
| posted invocation → native isVisible |48.632 /76.141 /81.229|44.565 /55.214 /55.214|
| ordinary service after visible |9.020 /37.171 /44.328|17.557 /19.513 /19.513|

Zero opening enumeration/icon deltas; normal UI/default bookkeeping, wrappers,
fixture quit, resources and workers cleanup. Native property+5ms observation is
not pixel latency; fresh-candidate cold is not reboot/OS-cache eviction.

## Startup service: retained inclusive failure

`regular-startup-service-r2-20261014`:38 frozen artifacts, actual executed independent
C sender,100 posts/receipts, sender0, no forced cleanup. The driver starts the
candidate in the same guest turn after a real calibration receipt. Native terminal
job clocks are captured before cancellation; new discovery-job drain and wrapper
restoration are independently verified. Original job identity/receivers/return values
and whole production effect batches are preserved.

- **Inclusive probe FAIL:** p9580.780/max366.779ms, startup request→return403.889ms.
- Recorded new discovery-image preparation146.431ms; remaining startup cost is not
  individually attributed. No ordinary metadata rows in this empty-guest probe.
- Actual off-main scan overlap:9 events, p95/max2.516ms; job duration about500ms.
- New discovery job drained after stop; normal cleanup. No slow events removed or
  unchanged rerun. The inclusive probe's fixed50ms/100ms gates were not passed.

The external calibration binding was armed **before** candidate:start(); configured
product bindings were installed afterward. Coordinator scopes this delivery to
best-effort functionality and running/settled chooser behavior, retaining cold
initialization as a documented performance qualification—not a running-command
budget waiver or an inclusive startup-service PASS. Full release hardening must
address initialization/service costs where required. Guest overlap is not host proof.

## Preserved failures / diagnosis

- d1542f635bb4 and a17286c51a89: strict startup completion failed,21 unresolved;
  first lacked status export, second captured it. Later best effort does not repair.
- 0801900ee9f0: temporary diagnostic loaded before module-path setup; harness error.
- 8e12059ae7a1:95 hashes, diagnostic21 targets; system targets consumed aggregate
  budget before ordinary B. Deterministic priority fixed starvation, not classification.
- dabc99914819: first best-effort run matched first A/B, selection and reopen; final
  cancellation failed a harness counter that recaptured later focus as startup focus.
  Counter now frozen at startup; original overall FAIL retained.
- a10743c60e34: scenario passed/normal guest cleanup, overall transport FAIL because
  trailing hotkey logs followed the JSON reply. Generic parser now requires exactly
  one JSON response line and rejects ambiguity; original FAIL remains.
- dbbe95085afc: first opening benchmark ordinary service60.802ms, p95 gate failed.
  Cause remains unknown; later terminal-wait populations do not repair it. Its
  cleanup boolean-JSON transport bug was separately diagnosed and fixed.
- regular-startup-service-20261014: first service probe inconclusive, coordinator
  delayed startup until the sender finished. Raw startup facts remain, no overlap
  certificate. Changed same-turn driver produced the valid inclusive failure above.

Temporary classification wrappers/proxy and runner flag were removed after diagnosis;
byte-identical ignored archive and immutable failed artifacts remain. No permanent
product diagnostics or extra polling. Native source/readiness faults have pure
coverage, not broad real-app certification.

## Desktop-entry retry cancellation correction — 2026-11-01

**Verified incident:** running frozen commit4bcef66 tracked only one D3 window
while an independent bounded native lookup resolved additional eligible Finder
and Chrome windows with no membership. The same process later tracked six D3
windows after ordinary user desktop use, without reload or corrective effects.
The startup attempt remained settled/incomplete56 unresolved. Missing membership
explains ineffective j/k and absence of a split; no captured trace proves the
original callback sequence or cause of the separately reported keyboard lag.

**Verified source defect:** regular entry schedules at most two100ms retries when
native exposure is delayed. `Host:setContext` canceled that timer even on a
same-desktop refresh. `_applyContext` handles such a refresh with reflow, not
rediscovery. Thus an early incomplete scan plus a duplicate/geometry context
observation can abort recovery and leave ordinary windows undiscovered until a
later entry or targeted lifecycle/readiness event. `hs.window.list(true)` is
onscreen-only (recorded above), so native Space membership alone is insufficient
to find those windows during entry animation. Startup is a separate best-effort
path; this correction does not make startup complete.

**Correction:** retain the existing finite entry retry on same-scope observations;
its callback checks display/regular-Space/type rather than context-table identity.
Departure and shutdown still cancel, the three-attempt budget is unchanged, and
no new scan, timer class, polling, or synchronous native work is added. A focused
regression fails before the change (same-scope refresh canceled retry), passes
afterward and confirms delayed admission. Existing departure/stop tests pass;
**360 Lua tests pass**, whitespace clean.

**Native acceptance:** reused owned guest10bucks-run-ft-eaa07ef31097, AX granted,
Secure Input off, three preexisting ordinary windows. Frozen candidate and two
owned fixture windows: B omitted from startup inventory, first entry owner hint
suppressed, same-scope context observation, then native hint restored before the
original retry. The retry remained owned, admitted B, and independent native
readback confirmed A-left/B-right split and actual B focus. No test frame/focus
repair was applied. This controlled event-boundary test proves the corrected
mechanism, not the exact historical host callback sequence or native animation.
No keyboard/latency certification or lag-fix claim.

First run setup failed because startup's actual-focus probe admitted B; original
failure retained. Second run suppressed only that startup observation to isolate
the entry retry, and passed. Production bytes unchanged between runs. Both runs:
fixture quit acknowledged/exit0, mailbox claims absent, candidate/timer stopped,
validity/discovery resources drained. Final guest retained three preexisting
windows. Ignored frozen/hash/controller/result artifacts:
`.pi/d3-retry-freeze-r{1,2}/`, `.pi/d3-retry-r{1,2}.sha256`,
`.pi/d3-retry-native.lua`, `.pi/d3-retry-native-r{1,2}.json` and
`.pi/d3-retry-{before,after,final}.log`. No host reload/hotpatch performed.

## Review and cleanup

327 Lua /66 Python checks, Lua/native syntax, Swift fixture build and whitespace
checks pass. Independent review challenged source authority, raw outcomes, failures,
query budgets, new-job lifetime and aggregate growth. One startup owner remains;
no global complete-discovery or cold-initialization responsiveness claim.

Owned guest cleanup verifies no ordinary test windows, original3 regular desktops/D1,
no running candidate/sender/observer and drained workers. Host remains frozen at the
previous ranking checkpoint until a separately authorized load is actually verified.
