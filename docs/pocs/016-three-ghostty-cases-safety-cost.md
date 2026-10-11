# Three exact Ghostty regressions and focused-query cost gate

## Status

**Three owned guest cases PASS; host silent-close repair remains BLOCKED.**
The proposed synchronous focused-resource safety tracker is **NO-GO** under its
fixed query-cost gates. No production polling/event expansion added.

## Host evidence

2026-10-11 host candidatee1c9462 manual failures preserved in ignored
`.pi/host-e1c9462-three-failures.json`:240transition rows/190dropped;
91explicit signal rows/zero dropped/errors; checked registrations accepted,
four observers running, four retained ended resources AXinvalid, zero explicit
destruction. Main/UI signals accompany focus signals; no recorded alternate
close event. Close timestamps are absent. Late removals occurred at navigation/
context boundaries. Some physical changes follow explicit SwapGroups/Move commands;
those are not evidence that layout toggles alone reordered state. Retained toggles
preserve cached assignments, but do not independently reconstruct every reported
visual failure. No speculative attribution to reducer, rendering or platform.

All diagnostic observers stopped successfully before candidate stop/full reload.
Host legacy26bindings/filter/reconcile/workspace/barTimer independently verified.
No user windows created/closed automatically.

## Exact native commands

Same running owned debug guest—no reboot between sessions:

```sh
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-close-recovery
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-column-normalization
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-layout-retention
```

All A/B/C are real same-process Ghostty1.3.1 windows. Environment/provenance:
macOS26.6.2/25G83, HS1.1.1, SIP/AX enabled, unlocked/noSecureInput,
single1024×768logical display, requiredsettings; executableSHA256/bundle/version,
strictcodesign/spctlaccepted-notarized and exact owned argv recorded beforelaunch.
No hostconfig/security edits, postclose navigation, focus repair, reflow, swap/move.

1. Columns createA/B/C: [A]|[B,C], Cfocused. RealCtrlD C → exactCAXinvalid,
   removal, unchangedA/Bsplit/order/selections, nativeBfocus.
2. Stack createABC; kB,kA; cycle → [A,B]selectedA|[C]selectedC, nativeA unchanged;
   lC; CtrlD C → [A]|[B], nativeBfocus (physical source-side recovery).
3. Columns[A]|[B,C], Cfocus → stackABC; kB,kA,jB → columns[A]|[B,C], Bfocus;
   repeat stack kA,kC,jA → columns samegroups, Afocus. Assignment/order retained;
   selections follow confirmedfocus. No structuralcommands in this oracle.

Gates unchanged:5s/checkpoint,250ms sampledstability,50ms sampling,
150ms matching-window freshness/gap,2logical-point frame tolerance. Expected native
frames come from fixed sequence/workarea, not candidate projection. Cached state
is a separate exact order/group/selection assertion.

Independent high reviewer joined literal expectations to raw native evidence:

| Session | Case | Hashes | Assertions/checkpoints | Minimum stability |
|---|---|---|---|---|
| a452311adf22 | occupied-column close |56/56|38/6|250.50ms|
| fc87ddef3212 | empty-column normalization |56/56|81/13|250.25ms|
| 0f24af553f4c | layout retention |56/56|146/23|250.17ms|

Artifacts under ignored `vm/results/10bucks-run-ft-eaa07ef31097/session-*/`.
All record normal unforced Ghostty/launcher/fixture cleanup, stopped observers/timer,
no pending task/action. Action-time trace gaps reach approximately497/450/397ms;
matching checkpoint windows pass, not uninterrupted-transition/performance evidence.
Reuse correctly means cold acceptance:false.28Python oracle tests pass,229Lua
unchanged; syntax/diff checks pass. These tests do not fix/explain host silence.

## Focused exact-resource safety-query POC

Existing POC012 plus checked host silence justify investigating a safety seam,
not introducing permanent polling without measurement. Read-only temporary host
probe retains one exact initially focused AX resource, calls onlyisValid at100ms,
30timed samples plus untimedvalid precondition; no enumeration, effects, removal
or native actions. Sampling timer and5sdeadline stopped aftercollection.

Fixed gates BEFORE execution:30successfulvalidreads; nearest-rankp95(sorted29/30)
≤1ms; median≤1ms; maximum≤5ms; everyacquisitionstartgap≤150ms. No retries or
threshold changes. Raw `.pi/focused-validity-cost.json` independently reanalyzed:

| Gate | Observed | Result |
|---|---:|---|
| successful valid reads |30/30|PASS|
| median≤1ms |0.163833ms|PASS|
| p95≤1ms |6.26125ms|FAIL|
| maximum≤5ms |17.619167ms|FAIL|
| start gap≤150ms |155.962333ms|FAIL|

Reviewer checked unit conversion, timestamps/gaps, percentile, replay and resource
validity; no harness/analyzer defect. Timing brackets synchronous pcall(isValid),
including scheduling/reentrancy overhead, not isolated nativeexecution attribution.
Gap measures main-loop service, not necessarily query causation. Valid narrow host
failure, not universalplatform evidence. Cheapmedian cannot override tail failures.

## Architectural blocker and next decision

No verified alternate closeevent; snapshot absence is notliveness. Synchronous
focused safetycheck fails its fixed cheap-query gate. No appconditional, event
expansion, permanenttracker, changedthreshold or rerun approved as hostfix.

**Hypothesis:** a smallest native asynchronous exact-AX worker can observe explicit
resource invalidity without blocking Hammerspoon’s mainthread, preserving exact
resourceidentity/lease authority/cancellation. It needs a deliberately specified
live POC (AXworker thread, boundedmessagehandoff, stale-result rejection, detection
and keyservicecost gates) before production design depends on it. No nativeworker
implementation or securitybypass is authorized by this result. Background silent
close completeness remains separate. Host legacy stays active; guest stopped
candidate/fixtures while VM remains running.
