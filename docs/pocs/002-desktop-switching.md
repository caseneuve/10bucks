# POC-002 — Existing regular-desktop switching

## Status

**Narrow asynchronous switch-and-return mechanism observed; responsiveness budget failed in the live sample.** The first attempt aborted in harness startup; the separately approved corrected retry confirmed both intended desktops and complete cleanup. This is not production acceptance, a statistical latency pass, or topology-only reorder evidence.

## Decision enabled

Select a non-spinning, SIP-enabled native-identity-based switching mechanism. Installed Hammerspoon `hs.spaces.gotoSpace()` synchronously waits for Dock AX and busy-waits its default 0.3-second stabilization period; do not use that implementation unchanged on the hotkey path. Native numbered shortcuts have not been proved to match filtered positional numbering, particularly after reorder or with noncontiguous macOS desktop names.

## Hypothesis

Opening Mission Control, yielding through bounded timers, resolving its AX list against a fresh ordered native topology snapshot, and issuing one `AXPress` can switch to an existing regular desktop without an explicit Lua busy wait. Only a subsequent watcher-triggered matching native snapshot confirms completion.

## Environment

- 2026-09-22; macOS 26.5, build 25F71; arm64; configured built-in display.
- Hammerspoon 1.1.1; separate Spaces true; observed `mru-spaces=0`.
- Branch `dev-engine-rewrite`, HEAD `a037817`; uncommitted pure workspace reducer/tests and contract updates, not composed or loaded.
- Accepted bar runtime remains active with 12 bindings; stopped previous runtime remains stopped. No reload/config/settings changes.

## Approved procedure and fixed bounds

Human approved a <=90-second probe: open Mission Control, switch to the next existing regular desktop, then return. No create/delete/reorder/window movement or settings change. Abort if fewer than two regular desktops, active source unavailable, Mission Control already open, pending managed focus, or changed topology.

The prepared harness yields 0.3 seconds before its first AX attempt, retries only list readiness at 50ms intervals for at most 2 seconds, issues at most one `AXPress` per leg, and requires watcher-triggered confirmation within 5 seconds. A 20-second overall deadline owns cleanup. A failed check aborts the run; any rerun requires approval. Return is attempted only after confirmed outward success and unchanged preconditions.

## Instrumentation / acceptance

- Aliased outward/return events and monotonic callback/open/action/confirmation durations; no native IDs or window contents exported.
- Independent temporary C process posts timestamped, tagged F18 events. A temporary Hammerspoon event tap consumes only that tag; send-to-tap-service delay is measured independently of Hammerspoon timers. This is synthetic event-tap service, not physical hotkey dispatch certification.
- Correctness requires both intended native identities confirmed, source restored, topology unchanged, and all probe resources stopped.
- Record latency against performance budgets honestly; two switches cannot establish statistical compliance. Topology-only reorder delivery remains a separate unresolved question.

## Results — first attempt aborted before native action

**Verified:** retained aggregate trace contains a `harness-start-error` at 36.647ms and cleanup at 298.974ms. There are zero key samples and no armed/open/press/Space-observation rows. Cleanup reports source unchanged, topology unchanged, and resources released. Fresh runtime check still reports started, 12 bindings, previous runtime stopped, one clock timer, no pointer tracker, and no pending global focus.

**Independently diagnosed harness defect:** a source reviewer incorrectly inferred that `hs.task.new(path, completion, nil, arguments)` was required from the optional-parameter documentation. The lead accepted that recommendation. A separate constructor-only check (no task start or native effects) returned `incorrect type 'nil' for argument 3 (expected table or function)`. The three-argument form `hs.task.new(path, completion, arguments)` was then confirmed accepted. This is a harness/API-overload error, not a macOS switching failure. The script was corrected and given setup-phase markers before the separately approved retry below.

Before the attempt, lead source review also corrected a separate mistaken boolean-only `AXPress` success check: the documented successful return is an AX element, not `true`. That correction occurred before any attempt and is not native evidence.

## Results — separately approved corrected retry

**Verified from the aggregate trace:** exactly one accepted AXPress per leg; both subsequently received a Space-watcher snapshot matching the intended native identity. Outward request-to-confirmation was **1320.362ms**, return **941.345ms**. Open-Mission-Control call durations were **2.644/1.176ms**; AXPress durations **0.588/0.739ms**. Maximum recorded probe timer/watcher callback body was **15.004ms**. These measurements do not separate OS animation from all other runtime work.

Finish occurred at 4117.188ms and automatic cleanup at 4379.334ms. Final checks found source restored, topology unchanged, no probe watcher/tap/timers or sender process remaining. The accepted manager stayed started with 12 bindings, previous runtime stopped, one clock timer, no pointer tracker, and no pending global focus. No reload/settings/create/delete/reorder/window-movement action occurred.

**Verified service-budget failure:** 53 diagnostic key-down events were received under the outward stage label; **12 exceeded 100ms**, with maximum **743.091ms**. A queued burst delivered at approximately 1671–1674ms, with successive source-to-service ages descending from 743ms to 31ms. This establishes a service delay in this run, not its cause. The stage label remains `out` during the post-confirmation pause; it does not by itself mean every sample was sent while the switch was pending. The oldest delayed sample was sent during the outward transition.

**Harness measurement limit:** the return leg's final confirmation immediately stops recording key samples, then terminates the sender and drains tagged events before releasing the tap. Queued return events can therefore be consumed without a recorded delay. Return data is right-censored and MUST NOT be reported as a return latency pass. There were 67 recorded events total (4 arming, 53 outward-labelled, 10 return-labelled), not 67 independent switches. No pooled p95 is used as a native switching performance certificate.

## Results — separately approved attribution run

The human approved one more <=90-second switch-and-return trace, with no reload or topology mutation. Temporary wrappers measured existing manager context/host methods and application enumeration, preserving function returns/errors and restoring original raw/inherited fields. The same native switch mechanism and 2s/5s/20s bounds were retained. To remove earlier censoring, successful cleanup waited for the independent sender's normal completion and all **240 key-down plus 240 key-up** events, including events queued during return. Source review preceded execution.

**Verified:** both target snapshots confirmed; source restored; topology unchanged; sender completed; all wrappers/watchers/tap/timers released. Cleanup finished at **13.360s**. Native request-to-confirmation was **1262.915ms outward / 1037.584ms return**. All 240 key-down delays were recorded; maximum **684.228ms**, with **17 over 100ms**. This remains a small two-switch attribution sample, not statistical certification.

| Instrumented inclusive boundary | Outward | Return |
|---|---:|---:|
| `manager:_contextChanged` | 593.951ms | 383.154ms |
| `manager:_startHost` | 583.752ms | 379.303ms |
| `Host:subscribeExistingWindows` | 575.839ms | 372.164ms |
| `Host:_attachApp`, 150 calls per leg | 320.352ms total | 255.548ms total |
| `application:allWindows`, 150 calls per leg | 217.075ms total | 86.796ms total |
| `runningApplications`, one per leg | 12.427ms | 10.261ms |

These are nested inclusive spans; do not add parent and child durations. The slowest single `allWindows()` took **121.346ms**. Standalone `Host:observeFocus` calls immediately preceding the context transitions took **76.186/54.259ms**. Thus observer registration and window enumeration dominate the measured context work, but are not its only native cost.

The oldest outward delayed key was sent at approximately913ms and serviced at1597ms. It overlaps the76ms focus observation at905ms, then the594ms context span at991ms. This ties the observed backlog to actual synchronous runtime work rather than blaming the timer-yielding AXPress alone. Return was also measured without the prior censoring: an event sent during the return transition waited **412.830ms**.

No source simplification was selected merely from the counters. Previously rejected cache/persistent-host changes must be inspected before any discovery or observation-lifetime replacement; missed undiscovered/inactive windows are not an acceptable latency optimization.

## Conclusion / production consequence

The narrow sample supports asynchronous timer-yielding Dock AX selection of an existing desktop by its current native topology index, followed by watcher/snapshot confirmation. It does not establish reordered topology delivery, rapid-input production behavior, or arbitrary topology interleavings.

The initial **743ms service delay** and attribution-run **684ms/413ms outward/return delays** exceed the100ms maximum budget. The first mechanism-only trace did not isolate cause; the later attribution run directly measured repeated observer registration/bootstrap consuming most context-transition time. This supports a focused runtime-boundary correction, not blindly reviving rejected cache/host rewrites or claiming all native costs solved. Keep the pure switching increment uncomposed until the next scoped decision. No thresholds were changed.

## Cleanup

All runs cleaned their owned resources. No sender started in the aborted attempt; the retry's sender was terminated and process absence independently checked. Lead-owned ignored `.pi/desktop-switch-probe.lua`, `.pi/desktop-probe-key.c` and executable, private `.pi/desktop-switch-probe-result.json`, and preserved `.pi/desktop-switch-probe-abort-01.json` remain solely for lead evidence review/reproduction, with no production imports or idle activity. The attribution helper `.pi/desktop-switch-attribution.lua` and its private result are also retained for lead-only diagnosis; all timing wrappers were restored. The stopped in-memory probe remains for aggregate inspection. Another live run requires human approval. The retry changed only active desktop and returned; no window or desktop was created, deleted, or moved.
