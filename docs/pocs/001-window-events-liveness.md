# POC-001 — Window events and liveness

## Status
hypothesis

This remains a pre-run protocol. A disposable POC-only observer currently
exists through step 2C (source comparison, targeted metadata/Space reads, and
pure correlation); no production runtime changed. Terminal manual regular-Space
move retry 005 and Chromium sample 006 are recorded below as narrow evidence
only. POC-001 remains `hypothesis`: neither sample selects a source or
destruction authority, establishes an action-to-detection latency result, or
advances the remaining live matrix. The companion
[`pocs/001-window-events-liveness/README.md`](../../pocs/001-window-events-liveness/README.md)
now freezes the separately gated AppKit fixture **implementation handoff**.
Its approved narrow source/test revision measures
`fixture_create_visible_completed` from `create_requested` using the public
AppKit occlusion callback and visible bit. The unapproved draft
[fixture--observer correlation research handoff](../../pocs/001-window-events-liveness/CORRELATION-HANDOFF.md)
defines the public-AX/SHA-256-alias candidate and explicitly authorizes no
implementation or live action. One approved
[fixture-only one-sample live-calibration](../../pocs/001-window-events-liveness/fixture/LIVE-CALIBRATION.md)
has now been recorded below. The [one-sample fixture--observer
live-correlation guide](../../pocs/001-window-events-liveness/LIVE-CORRELATION.md)
has now completed once, as recorded below. **POC-001 remains `hypothesis`; these
documents authorize neither another fixture action nor a POC-001 live action.**

## Decision enabled
Select the narrowest Hammerspoon window-observation combination (`hs.window.filter`,
direct application/UI-element watchers, or a combination) that supplies the
normalized lifecycle events required by the target adapter. Select an
authoritative permanent-destruction path and an event-triggered, targeted
manual regular-Space-move check if callbacks alone do not establish the move.

The decision must preserve LIFE-001/LIFE-002, FS-002, WIN-004 through WIN-006,
STATE-004/STATE-005/STATE-008, DISC-001/DISC-002, and PERF-001/PERF-002. It
must not authorize `_orderedwinids()`, visibility, z-order, or an eligible
snapshot as liveness evidence.

The fixture's `fixture_create_visible_completed` fact is narrower still:
AppKit reported at least partial visibility for its exact fixture window. It
MUST NOT imply liveness, unobscured pixels, AX readiness, Space ownership,
admission, or Hammerspoon observation, and it MUST NOT be used for
destruction. Therefore STATE-004 remains intact: neither this visibility fact
nor its absence removes membership. STATE-005 remains intact: a missing,
delayed, non-visible, wrong-object, or duplicate callback is uncertainty, not
destructive evidence. The frozen fixture procedure and its 30-warm/5-cold
`fixture_create_visible_completed - create_requested` thresholds live in the
fixture handoff; they are fixture-local and do not satisfy this POC's readiness
or destruction gates.

## Hypothesis
A POC-only Hammerspoon observer can, without permanent polling or a global AX
enumeration from a steady-state callback, correlate application and window
callbacks plus bounded event-triggered targeted observations so that each
covered lifecycle condition (minimized, application-hidden, native-fullscreen,
and inactive regular Space) remains independently represented as a tri-state
observation. Candidate filter/direct-AX facts remain isolated while they are
compared; only app hide is shared. Permanent removal has authoritative evidence
or a bounded targeted check, and a manual
regular-Space move is detected within its bound.

This is falsified by any false death in the covered matrix; by lifecycle facts
that cannot be distinguished under an overlap or callback ordering; by no
reliable authoritative destruction path and no bounded targeted alternative;
by an undetected/tardy manual move; or by a stated latency/query threshold
below being missed.

## Environment

The following are **observed environment values**, not stable detection
contracts. Except where a result explicitly records its run-start values, they
provide host context only and do not identify a sample's execution environment.

- **Observed** (`sw_vers`): macOS 26.5, build `25F71`.
- **Observed** (`uname`; `hs.screen`): `arm64`; one Built-in Retina Display.
- **Observed** (`hs.processInfo`): Hammerspoon 1.1.1.
- **Observed, earlier pre-sample capture** (`git rev-parse --short HEAD`; `git
  branch --show-current`): 10bucks commit `5a03f04` on
  `dev-poc-001-window-events-liveness`. This is not asserted to be the
  Chromium sample 006 execution revision; its retained aggregate below does
  not include a commit field. Every future live sample must record its actual
  execution commit and branch at run start.
- **Observed** (`csrutil status`): SIP enabled.
- **Observed** (`defaults`): menu auto-hide value `1`; `mru-spaces` value `0`;
  separate Spaces `true`.
- **Observed** (application version metadata): Chrome 152.0.7977.77; Slack
  4.52.155; Signal 8.26.0; Thunderbird 153.1.1; Claude 1.44121.4; zoom.us
  7.1.5 (84650).
- **Observed** (`/System/Applications/Utilities/Terminal.app/Contents/Info.plist`): Terminal 2.15 (build 470.2).

Do not generalize these values into portable detection behavior. Values observed
while running must be timestamped in Results and identify whether they came from
an OS UI, a command, or the Hammerspoon host.

## Procedure

### 1. Preflight and isolation

1. Record the Environment fields, POC branch/commit, test date, and whether
   each sample is warm or cold. Do not run if any required environment fact is
   unknown; mark the affected result unmeasured instead.
2. Stop the legacy 10bucks runtime before loading any POC harness. Use the
   existing `spoon["10bucks"]` global, explicitly verify `started == false`,
   and load the observer directly from its absolute repository path; do not
   alter the init/load path or call `hs.reload`. Record `legacy_stopped` only
   after confirming that no legacy 10bucks watcher, reconciliation timer, bar
   timer, or hotkey remains active. The observer performs zero frame, focus,
   minimize, hide, fullscreen, move, close, or other window effects.
3. Start one disposable POC-only observer configuration. It may subscribe to
   candidate sources in parallel for comparison, but it is not a production
   path and is deleted after the POC unless separately justified. Emit
   `run_start` and an inventory marker naming enabled candidate sources. The
   currently approved calibration uses only explicitly named human Terminal
   actions; it has no autonomous action driver or mutation loop. Never run the
   observer and legacy runtime concurrently.
4. Prepare the representative matrix: Terminal, a Chromium-based browser or
   Chromium app, Slack, Signal, Thunderbird, Claude, and Zoom. For every app,
   create a redacted app label and native window ID mapping. Do not put titles,
   message previews, URLs, account names, or document paths in committed data.
5. Prepare two regular Spaces and, where the OS permits, a native-fullscreen
   Space. For cold samples, first establish and record the requested cold
   state: application not running for creation; POC host freshly loaded with
   no retained handle cache for bootstrap; or window pre-existing on an
   inactive Space, minimized, hidden, or native-fullscreen. A cold state is
   invalid if the relevant app/window/metadata has already been observed by
   the POC host in that run.

### 2. Clocks, markers, and correlation

All timestamps use one monotonic clock exposed by the POC host, in milliseconds.
Each trace line includes `run_id`, `sample_id`, `window_id` (or a one-way
redacted token), `source`, `sequence`, and `monotonic_ms`.

Use these markers exactly:

- `action_target_binding_armed` / `action_target_binding_hotkey_result`:
  the POC-only one-shot binder's armed state and its bound/rejected outcome.
  The result records no raw focused-window identity. The retry guide uses
  `⌃⌥⌘B` (physical Control, Option/Alt, and Command held while B is tapped
  once); the binder deletes/disarms before it reads focus and does not issue an
  effect. A later arm is allowed only after the prior bound action's completion
  marker clears its active target; it rejects while armed or active.
- `action_begin`: the guide announces a manual action immediately before
  performing it, or explicitly directs the separate controlled action driver
  to issue the named native action.
- `native_action_completed`: only the separate, explicitly human-directed
  action driver emits this, and only from its native completion hook (for
  example, close completion or the driver's post-action completion callback).
  For representative-app manual actions without such a hook, the guide records
  `manual_visual_complete`; those samples are correctness/event-coverage
  evidence only and cannot claim action-to-detection timing.
- `callback_enter` / `callback_exit`: entry and return of each Hammerspoon
  callback, including its event source and payload facts.
- `targeted_check_begin` / `targeted_check_end`: every event-triggered
  `windowSpaces(windowId)`, `windowsForSpace(spaceId)`, or other selected
  per-window/per-Space check, including trigger callback sequence.
- `normalized_event_enqueued`, `lifecycle_fact_committed` (POC model only),
  `destruction_candidate`, `destruction_paired_candidate` (diagnostic only;
  neither is `destruction_confirmed` or an authority choice),
  `destruction_confirmed`, `space_move_confirmed`, `readiness_confirmed`, and
  `metadata_ready`, and `lifecycle_source_conflict`: POC correlation outcomes.
  Lifecycle facts are tri-state: unknown is not false. Filter/direct-AX
  minimize/fullscreen candidates are emitted separately; a conflict records
  uncertainty rather than overwriting either source. `metadata_ready` means
  only the agreed privacy-safe metadata fields were available; it makes no
  ownership/admission claim. Step 2C MAY emit one idempotent,
  non-effecting `window_ready_eligible` only after independently confirmed
  regular ownership; focus itself never admits. None performs production state
  mutation or any window effect.
- `global_ax_enumeration_begin` / `global_ax_enumeration_end`: every broad AX
  or all-application/window enumeration attributable to POC harness calls.
  That counter must remain zero in steady callbacks. Candidate-source internals
  are recorded separately as evidenced, ruled out, or unknown as described in
  Instrumentation; the harness counter does not claim visibility into C or
  framework internals.
- `next_key_sent` / `next_key_serviced`: a benign POC hotkey sent while a
  callback or targeted check is pending; retained to expose main-thread stalls.

The observer/action-driver setup must log a platform-provided source event
timestamp when a source provides one. **OS callback-arrival latency** is `callback_enter -
source_event_timestamp`; it is reported only when that source timestamp exists
and uses the same clock or a recorded clock conversion. If no comparable source
timestamp exists, report arrival latency as `unmeasurable`, never as zero and
never as callback duration. **Harness processing duration** is
`callback_exit - callback_enter`, with targeted-query time reported separately
as `targeted_check_end - targeted_check_begin`. The destruction deadline is
`destruction_confirmed - native_action_completed`; manual timing is explicitly
not substituted for this controlled marker. Readiness is
`metadata_ready - readiness_trigger` for warm metadata observation, and
`readiness_confirmed - cold_trigger` for cold discovery; each trigger is named
in the trace. `metadata_ready` is a non-effecting metadata marker, not an
eligibility/admission marker; POC-001 issues zero frame effects.

### 3. Guided matrix

The full matrix below remains **pending**. The first Terminal-only calibration
was diagnostic-only, retry 005 is narrow move evidence only, and Chromium
sample 006 is the completed narrow create/focus/covered/two-temporary-close
sample recorded in Results. Do not infer authorization for minimize/hide/
restore, fullscreen, Space movement, cold bootstrap/reload, rapid repetitions,
another app, true Chromium last-window behavior, or the representative-app
matrix. The fixture's source/test-only occlusion revision is frozen in the POC
README; it requires separate approval before any build, launch, observer
integration, or live run.
For Terminal and the Chromium representative first, then each remaining
representative app where its UI supports the action, run the following and
retain every event order, including failures and late callbacks:

1. Mark `create_first`, then create a first and an additional standard window;
   exercise focus/unfocus and rapid create → focus → close. Run warm creation
   samples and controlled cold launches. Observe readiness metadata, actual
   regular-Space ownership, the non-effecting `metadata_ready` marker, the
   idempotent non-effecting `window_ready_eligible` intersection, and
   duplicate/delayed readiness.
2. Mark `close_foreground`, `close_background`, and `close_last`; at explicit
   human direction, use the separate controlled action driver where available
   to close those windows. Repeat with a background/covered window. Correlate
   callback sources, app termination, and
   authoritative destruction/targeted-check outcome.
3. Mark `covered`; completely cover a still-open stacked window, then cause
   unrelated focus/title activity. Hold it covered through the observation
   window. It must remain live and no destruction check may infer death from
   visibility, onscreen state, or ordering.
4. Mark `minimize_hide_overlap`; execute minimize → hide application → unhide
   → restore. Repeat at least the order variants hide → minimize, restore →
   unhide, and unhide → restore. Include an app with one minimized and one
   non-minimized window. Verify the three relevant facts independently after
   every callback, not merely after the final UI state.
5. Mark `fullscreen_enter` and `fullscreen_exit`; manually enter and exit
   native fullscreen. Repeat one overlap such as minimize before fullscreen
   where macOS permits, otherwise record it unsupported rather than inferring
   behavior. Verify native-fullscreen remains distinct from minimize and app
   hiding and that leaving fullscreen does not erase another condition.
6. Mark `move_regular_space`; use Mission Control, title-bar, or an available
   native edge mechanism to move an open managed-candidate window from regular
   Space A to regular Space B. The initial callback must trigger only the
   selected bounded targeted observation(s), not a recurring poll. Repeat with
   source/destination inactive and with a covered window when feasible.
7. Mark `quit_relaunch`; quit and relaunch the app, including a last-window
   close where the app stays alive and a true application termination. Distinguish
   the two observations.
8. Mark `cold_bootstrap`; reload only the POC host (legacy remains stopped)
   with pre-existing windows on active and inactive regular Spaces, and with
   pre-existing minimized, hidden, and native-fullscreen windows. Do not turn
   focus itself into admission; record any independent targeted readiness
   result and defer uncertain ownership.

For each timed controlled action, issue `next_key_sent` while any AX/Space
check is outstanding. Keep all POC timers bounded to the sample timeout and
stop them at sample completion; there is no permanent poll.

### 4. Sampling, analysis, and stop conditions

- Collect at least 30 warm timing samples and at least 5 cold timing samples
  for each meaningful creation/readiness path and callback-processing class.
  Report count, median, p95, maximum, timeouts, and late completions.
- Destructive close/quit cases use 10 controlled samples per available class
  (foreground, background/covered, and last-window) rather than 30 because
  each destroys/recreates user-visible application state and repeated app
  authentication/recovery would contaminate timing. This reduced count is
  evidence only for the stated classes, not a general p95 claim.
- Native-fullscreen entry and exit use 5 samples each per available app because
  each creates/removes a dedicated Space and visibly disrupts the guided
  workspace; report every raw sample and do not generalize beyond the tested
  app/OS state.
- Stop the affected path immediately after a false death, an unintended global
  AX enumeration in a steady callback, an unbounded/repeating check, a privacy
  leak, or a timeout. Preserve the trace, redact it, and mark the path failed
  or unresolved; do not tune thresholds after observing it.

## Instrumentation

The POC-only harness records candidate `hs.window.filter`, direct
`hs.application.watcher`, and direct UI-element/window watcher callbacks with
source identity, raw event name, native IDs, and normalized facts. It records
app launch/termination/hide/unhide; focused window and active Space; targeted
`windowSpaces(windowId)` and `windowsForSpace(spaceId)` inputs/results;
visibility, minimized, native-fullscreen, role/subrole, and capability metadata.

It also records callback entry/exit, every harness-attributable query attempt,
timer create/cancel/fire, and the counters below. Step 2C attributes and times
`windowSpaces(windowId)`, `windowsForSpace(spaceId)`, `activeSpaceOnScreen()`,
and `data_managedDisplaySpaces()` topology snapshots. It uses one topology
snapshot to classify all IDs and deliberately does not call `spaceType()` per
ID. Raw IDs remain in memory only; traces export aliases/results only. Candidate sources may run
concurrently only to compare evidence; no source may mutate 10bucks state or
cause a window effect. POC-001 records zero frame effects and has no synthetic
frame-request marker.

For each candidate source, query evidence has two distinct scopes. First, wrap
or intercept every Hammerspoon/Lua query entry point invoked by the POC harness
and attribute it to callback sequence/source; these produce the frozen
"POC-issued" counters. Second, establish framework-internal global-refresh
behavior by applicable Hammerspoon source inspection and/or instrumented
interception at the lowest available boundary, recording the exact version,
method, evidence, and blind spots. If an internal call cannot be observed or
ruled out (including a C/framework path), report it `unknown`, not zero. A
candidate whose steady-state global refresh cannot be ruled out cannot satisfy
the selected production path/query gate.

Required counters per sample and aggregate:

- POC-issued global AX enumerations, all-window snapshots, and
  all-application scans, each attributed to its harness call site; and,
  separately, candidate-framework global-refresh evidence classified as
  observed, ruled out, or unknown;
- targeted liveness/Space checks, grouped by trigger callback;
- callback count/duration and queue/normalization duration;
- duplicate, delayed, missing, timed-out, and late callbacks;
- POC window effects (all expected zero), active timers, and next-key service;
- event-triggered checks after a manual Space move and any repeated check after
  the sample settles (expected zero).

Raw traces remain local until redacted. Commit only redacted tokens, event
names, timing values, counts, OS/app versions, and a summary. Hash or replace
native IDs consistently per run; remove titles, URL fragments, message text,
file paths, personal names, account identifiers, screenshots containing them,
and any raw AX attributes that expose them.

## Acceptance threshold

All thresholds are fixed before the run:

1. **No false death:** zero removals/`destruction_confirmed` outcomes for every
   live covered, hidden, minimized, inactive-regular-Space, or native-fullscreen
   window in the covered matrix. Neither visibility nor one snapshot may be
   cited as destruction evidence.
2. **Permanent destruction:** either (a) an authoritative destruction or owning
   application-termination event is correlated for every tested close/quit
   class, or (b) an event-triggered targeted liveness check has a defined
   bounded timeout and proves destruction without a global scan. In either
   case, `destruction_confirmed - native_action_completed <= 1,000 ms` for all
   controlled successful destruction samples; timeouts/late completions fail
   the path rather than being discarded.
3. **Independent lifecycle facts:** minimized, app-hidden, native-fullscreen,
   and inactive-Space facts are independently distinguishable under every
   tested overlap/order. Every unobserved condition remains unknown; it MUST
   NOT become false because a callback is absent. Filter/direct-AX candidates
   remain separate and contradictory observations emit uncertainty. For each
   candidate, clearing one never reports availability while another observed
   unavailable fact remains. Any unavailable condition prevents availability;
   membership/liveness is retained.
4. **Manual regular-Space move:** an event-triggered targeted observation
   confirms source removal/destination ownership without permanent polling;
   after settling, targeted-check count remains unchanged until another trigger.
   The authorized manual move has no controlled `native_action_completed`
   marker, so its action-to-detection timing is unmeasurable and makes no
   two-second claim. A later controlled-driver experiment must define its own
   timing threshold before it runs.
5. **Creation/readiness:** for each meaningful warm creation/readiness path,
   `readiness_trigger → metadata_ready` has p95 <= 100 ms when all agreed safe
   fields are available. `metadata_ready` remains non-effecting; Step 2C adds
   `window_ready_eligible` only for its idempotent intersection with exactly
   one confirmed regular owner. POC-001 issues zero frame effects. A cold path reaches
   `readiness_confirmed` or an explicit
   deferred-uncertainty result within <= 3,000 ms. An uncertain cold window is retained/deferred, not
   admitted or destroyed on guesswork; uncertainty beyond that bound is
   reported as deferred/unresolved, never claimed ready.
6. **Callback/main-thread service:** harness processing duration has p95 <= 50
   ms and maximum <= 100 ms for steady callbacks. The benign pending-work
   hotkey has p95 <= 50 ms and maximum <= 100 ms from `next_key_sent` to
   `next_key_serviced`. OS callback-arrival latency is separately reported or
   explicitly unmeasurable and does not substitute for either gate.
7. **Query discipline:** zero POC-issued global AX enumerations, all-window
   snapshots, or all-application scans from steady callbacks. Startup bootstrap
   or an explicitly invoked recovery experiment is separately labeled and is
   not counted as steady-state evidence. Separately, source inspection or
   instrumented interception must rule out a candidate source's steady-state
   global refresh; `unknown` framework/C behavior fails the selected production
   path/query gate rather than being treated as zero. Zero permanent lifecycle
   polling.
8. **Evidence volume:** satisfy the warm/cold and explicitly reduced destructive/
   fullscreen sample counts in Procedure. Smaller samples cannot establish a
   broad latency claim; unsupported app actions remain explicitly unmeasured.

## Results

### Aborted pre-sample startup — harness evidence only

- A later attempt to begin the approved Terminal lifecycle calibration aborted
  during observer startup, before any sample marker or human UI action. The
  direct window watcher was a real `hs.uielement.watcher` userdata; the harness
  attempted to assign diagnostic aliases to it and startup failed. The
  orchestrator immediately stopped the partially started observer and restored
  legacy 10bucks. No trace sample, lifecycle action, measurement, or macOS
  behavior claim resulted from this aborted attempt.
- The harness now keeps each direct watcher and its redacted app/window aliases
  in a separate plain-Lua record, and pure fakes cover userdata-like assignment
  rejection plus transactional cleanup after a later startup-stage failure.
  This is harness bookkeeping evidence only; no Hammerspoon/live run was
  performed for this checkpoint.

### Interrupted Terminal lifecycle sample — export pending

- The minimize action completed. The user then hid Terminal and manually
  returned by unhiding it because hiding Terminal also hid the conversation/
  session window.
- The orchestrator initially interpreted the user's message as inability to
  continue, marked the sample aborted, stopped the observer, and restored
  legacy 10bucks.
- The private export then failed closed because `current_uid` parsed terminal-
  title escape-sequence output before the actual UID. The stopped trace remains
  in Hammerspoon memory pending export through the corrected private-export
  module.

This is neither a clean hide/unhide marker sequence nor a pass/fail result.
It makes no lifecycle, timing, or source-authority claim.

### Aborted Terminal lifecycle sample — redacted observer aggregates

**Observed:** the previously pending stopped trace was exported privately and
reviewed locally. This remains an aborted, read-only sample, not a clean
hide/unhide completion and not a completed lifecycle calibration. The raw trace
and its aliases are not copied here.

- The same redacted alias received direct minimize and then filter minimize
  callbacks **2.907 ms** later. This is one observed ordering, not a source
  authority or timing claim.
- Actual application `hidden` and `unhidden` callbacks were observed **17.373
  s** apart despite the abort. The minimized alias remained unavailable after
  unhide; source-specific unknowns were preserved rather than converted into
  agreement or false.
- Of 16 aliases with metadata observations, **15** became metadata-ready;
  **4** reached the non-effecting eligible intersection; **1** remained
  uncertain. These are harness observations, not readiness/admission results.
- **53** completed callbacks had harness processing median/p95/maximum
  **6.250/18.960/28.701 ms**. No comparable source timestamp exists, so this
  makes no callback-arrival or acceptance-threshold claim.
- Steady callbacks issued **zero POC-issued global calls**. The sample had no
  timers or POC effects. POC-owned watcher cleanup balanced **147 attachments
  and 147 detachments**.
- There is explicitly no clean hide/unhide completion marker, restore action,
  native-fullscreen action, controlled completion marker, or timing/pass claim.
  Destruction, move, source selection, framework-internal refresh, and all
  other source-specific unknowns remain unresolved.

### First Terminal calibration — calibration-only observations

This is **not a pass/fail result** and does not advance the pending matrix or
select a production source/authority. The raw private trace was reviewed
locally and is neither committed nor copied here. The following redacted
aggregates are the only retained calibration observations:

- Export contained 3,201 schema-valid redacted event objects. It initially had
  mode `0644`; it was immediately remediated locally to `0600`. This exposed a
  harness defect: shell `umask 077` did not constrain the already-running
  Hammerspoon process, while `io.open(..., "w")` did not enforce a mode. The
  harness now fails closed through an existing owner-private directory,
  temporary write, fixed `/bin/chmod 600`, mode verification, and atomic
  rename; the operator guide retains the private-directory setup as defense in
  depth.
- The observed action stream included an **unplanned deviation**: the cancelled
  `terminal_focus_other_blank` was followed by `terminal_reveal_focus_other`.
  That action was outside the approved four-action guide. This calibration is
  therefore not a clean protocol sample; later guides must stop/mark an
  explicit cancellation rather than continue with a reveal/focus action.
- There were 98 callback pairs, 906 query attempts (296 bootstrap, 610 steady),
  and zero POC-issued steady global queries. Ownership produced 85 observations
  (81 steady topology snapshots and `windowSpaces` reads); no Space watcher
  callback or `space_move_confirmed` occurred. These counts are diagnostic,
  not a query-gate result.
- All 72 direct metadata attempts were uncertain because the callback/window
  objects did not support the assumed `attributeValue` method. The callback
  shape did expose the narrow public methods `isMinimized`, `isFullScreen`,
  `role`, `subrole`, and `isVisible`; the POC now uses those only when present,
  attributes each field, reads complete readiness metadata only on
  bootstrap/create/focus, and retains cached safe fields across move/resize
  lifecycle reads. Visibility was not used as liveness evidence.
- One close-area observation had a direct AX destruction candidate and a filter
  destruction candidate for the same redacted alias 0.552 ms apart. No
  controlled `native_action_completed` existed, no `destruction_confirmed` was
  emitted, and no destruction authority is selected. The POC now records
  independent direct/filter candidates and only an idempotent paired-candidate
  diagnostic in either callback order.
- Callback processing (98 samples) had median/p95/max 8.120/20.802/28.420 ms;
  targeted topology reads (85) had 5.544/8.320/9.464 ms. These are limited
  calibration observations, not threshold claims.

The pure fake suite covers regular bootstrap ownership, fullscreen/unknown,
confirmed A→B move, same-Space duplicate, ambiguous deferral, callback query
attribution, bounded active-Space known-window sweep/no timer, metadata method
shape/partial cached merge/readiness/uncertainty, paired destruction candidates
in both orders, watcher attach/detach diagnostics, and fail-closed export.
Pure coverage is not live evidence.

### Fullscreen calibration 003 — redacted diagnostic results

**Observed (private trace analysis; not a broad POC decision):** Terminal native
fullscreen entry ordered direct resize/property observation, fullscreen
ownership, then filter fullscreen; exit ordered a Space callback still showing
fullscreen, direct resize/property false, regular ownership, then filter
unfullscreen. The same prior confirmed regular owner was observed again after
exit. There was no false regular-Space move and no destruction confirmation.

- The ownership trace now records membership count, reciprocal-confirmed count,
  reason (`unique_regular`, `fullscreen`, `ambiguous`, `query_error`, or
  `missing`), and retained prior regular owner. It emits `no_regular_move` for
  fullscreen, unknown, and same-regular results; only reciprocal unique regular
  A→B evidence can emit `space_move_confirmed`.
- The trace contained 40 callbacks: median/p95/maximum processing duration was
  **5.66/71.14/85.84 ms**. The four Space callbacks caused the maximums. This
  calibration therefore **fails the callback p95 ≤ 50 ms threshold**; the
  threshold is unchanged. It has no pending-work next-key measurement.
- It recorded **4 Space callbacks and 53 ownership queries**. The former sweep
  took a topology snapshot per known alias, so this diagnostic exposed callback
  amplification rather than a move result.
- Before a manual regular-Space move, the POC-only harness was corrected and
  pure-tested to take one topology snapshot and one active-Space read per
  non-coalesced sweep, reuse that topology for every known-window reciprocal
  probe, count unique known windows and exact sweep query attempts, and emit an
  explicit coalesced duplicate outcome for the same active Space/generation.
  It retains no timer.
- A read-only target-bound action marker now queries focused window once,
  resolves only its existing in-memory redacted identity, records its confirmed
  or currently observed regular owner when available, and otherwise rejects the
  binding. Focus does not admit. Destruction candidates during a bound action
  are labelled target/non-target only; none is confirmation.

The raw trace remains private and is not committed. This small fullscreen-only
sample does not select an event source, destruction authority, move algorithm,
or broad POC pass/fail result.

### Aborted manual regular-Space move 004 — no target binding or move

- **Observed:** the operator could not generate
  Control-Option-Command-F12. The attempted key press inserted non-sensitive
  terminal junk instead. The raw trace and inserted text are not copied here.
- **Observed:** this happened before the target binder fired and before any
  target binding or manual regular-Space move. The orchestrator marked the
  sample aborted, stopped the observer, exported its trace with mode `0600`,
  restored legacy 10bucks, and verified the binder was disarmed.
- **Conclusion:** 004 is aborted history, not a result for event ordering,
  ownership, latency, source selection, or manual-move detection.

### Manual regular-Space move retry 005 — narrow observed result

- **Verified:** the bound target had unique reciprocal regular ownership
  `space-001→space-002`. No direct `AXWindowMoved` or filter
  `windowMoved` event occurred. Detection came only after destination
  activation: `activeSpaceChanged` ran one bounded sweep of six known windows
  and confirmed the target's reciprocal destination ownership.
- Each non-coalesced active-Space sweep used one topology snapshot and reused
  it across the known-window sweep. There was no timer, poll, window effect,
  global steady-state query, or false target death. The target did not produce
  a false move; non-target destruction observations remained candidate-only.
- Callback processing is calibration only: n=13, median/p95/maximum
  **8.920/37.160/37.160 ms**. There is no source-action timestamp or
  pending-work key-service measurement, so retry 005 makes no timing claim.
- This does not establish direct/filter move delivery, a destruction authority,
  duplicate-callback coalescing, a production algorithm, or detection for a
  move where neither source nor destination activates. That inactive/no-
  activation case remains unknown.
- Chromium sample 006 is recorded below. Its two temporary closes do not make
  a true Chromium last-window result; that behavior remains pending. No next
  live action is authorized by this document.

### Chromium create/focus/destruction sample 006 — redacted aggregates

**Observed, narrow only:** the private, schema-valid
`chromium-create-focus-destroy-006` export was analyzed locally and is not
committed. It contains no raw IDs, titles, URLs, or AX values in this document.
The observer stopped cleanly, no callbacks remained open, and its final
`cleanup_complete` count was zero.

- The two destructive binds resolved two distinct temporary-window aliases
  (called **first bound temporary window** and **second bound temporary
  window** here). The retained regular owner at each bind was confirmed. No
  application alias is retained in this result.
- Both temporary closes produced one filter `windowDestroyed` candidate and
  one direct `AXUIElementDestroyed` candidate for the bound target. Filter was
  first in both pairs; direct followed by **0.278 ms** and **0.507 ms**,
  respectively. The filter missed neither observed close. These remain paired
  candidates only: there was no `destruction_confirmed`, authority selection,
  or general delivery guarantee.
- The protocol's covered-window marker did not name an alias. For the eventual
  first bound close target, no destruction candidate appeared before its close
  pair. That is no false-destruction observation for this eventual target, not
  proof that every covered window is safe.
- There is no controlled native-close completion marker, so there is no
  confirmation/latency result. The sample intentionally excluded a true
  last-Chromium-window close.
- Completed callback processing duration was **n=230**, median **3.862 ms**,
  nearest-rank p95 **33.013 ms**, maximum **91.586 ms**. These are harness
  processing durations, not callback-arrival or next-key-service latency.
- The 130-callback `AXWindowResized` burst produced 650 direct-window query
  attempts (five per callback). Fourteen non-coalesced active-Space,
  known-window-only sweeps occurred on the prescribed chat-switch path; each
  covered 6–8 known aliases and used 10–14 ownership queries (181 total).
- The export reports zero POC-issued steady global queries; it contains no
  timer creation/cancellation/fire, permanent poll, or POC window effect.
  This does not settle the separately recorded framework-internal filter
  refresh caveat.

**Target instrumentation correction, evidence-driven:** the observed resize
amplification justifies narrowing only the direct `AXWindowResized` ownership
path. Resize still reads targeted minimized/fullscreen properties. It probes
Space ownership only when `native_fullscreen` is newly known or changes from
its cached value; unchanged successful reads emit
`ownership_check_skipped` with `reason=resize_fullscreen_unchanged`.
`AXWindowMoved` continues to probe ownership on every event. If the fullscreen
method is unavailable, the observer records `metadata_uncertain` and an
explicit non-effecting skipped record (the same reason with
`fullscreen_status=unavailable`); it intentionally retains prior confirmed
ownership rather than inferring a move, liveness change, or destruction. This
is POC instrumentation only, not a production adapter decision. Pure-fake
coverage verifies repeated same-fullscreen resize skips, both fullscreen
transitions probe, moved always probes, and unavailable resize is
non-destructive.

### Fixture--observer one-sample correlation smoke — recorded result

**Observed, one controlled fixture only:** after isolating the POC module load
from stale Hammerspoon `package.loaded` entries, the fixture and observer
produced exactly equal full correlation aliases. The observer performed one
window-element construction and one `AXIdentifier` read. Its correlation map
contained one entry before close and zero after explicit finish.

Both candidate destruction paths retained the alias. Relative to the fixture's
native close completion, the direct AX candidate arrived after **1.961 ms** and
the filter candidate after **5.639 ms**. Maximum callback processing duration
was **28.413 ms**. The stopped export reported zero steady global queries, zero
open callbacks, zero timers, and zero window effects. The fixture process and
socket were absent afterward, and legacy 10bucks was restored and verified
running.

The operator used bounded external status checks while awaiting callback
delivery; the observer itself used no timer or poll. This one sample proves only
the privacy-safe fixture--observer join and candidate alias retention. It does
not establish p95, liveness, destruction authority, readiness, representative-
app behavior, or POC-001 completion. The separately approved volume attempt is
recorded below.

### Direct-AX fixture correlation smoke — recorded result

**Observed, one corrected controlled fixture:** selecting the direct application
`AXWindowCreated` callback produced exact fixture/observer alias equality after
one targeted conversion of the delivered Hammerspoon window wrapper to an AX
element and one `AXIdentifier` read. The unselected filter correlation path
performed zero element constructions and zero identifier reads.

- direct targeted AX-element conversions: **1**;
- direct `AXIdentifier` reads: **1**;
- exact full alias equality: **true**;
- correlation map before close/after finish: **1/0**;
- alias-bearing destruction candidates: **2** (direct AX and filter);
- direct/filter candidate latency after native close: **3.173/7.177 ms**;
- maximum callback processing duration: **22.012 ms**;
- POC-issued steady global queries, timers, window effects, and open callbacks
  after cleanup: **0**.

A prior attempt called `attributeValue` directly on the delivered Hammerspoon
window wrapper and returned `attribute_read_error`. The orchestrator verified
that as a harness API-shape mistake against retained evidence and installed
Hammerspoon source; it is not classified as a platform failure and was corrected
before this recorded smoke. The corrected run removed its fixture process and
socket and restored legacy 10bucks.

This single sample proves only the privacy-safe early direct-callback
correlation and alias retention. It does not establish p95, representative-app
behavior, readiness/admission, liveness, or destruction authority.

### Fixture--observer correlation volume — stopped warm class; five cold samples

**Observed, approved volume attempt:** the warm class stopped during sample 2,
as required by the fixed stop rule. Warm sample 1 completed exact alias
correlation and both destruction candidates. The fixture then created and
reported its second window, and the direct application AX watcher delivered
`AXWindowCreated`, but no fixture-scoped `hs.window.filter` creation callback
formed the correlation map. The observer retained uncertainty and the runner
aborted the class without a third create. One direct callback in this sequence
took **426.587 ms**, exceeding the 100 ms maximum. Cleanup succeeded and this
was independently verified from the private export; it is not an analyzer-only
failure.

The separately defined cold class completed all five first-create samples:

- exact full alias equality: **5/5**;
- identifier construction/read: **1/1 per sample**;
- direct AX destruction-candidate latency: median **1.943 ms**, p95/max
  **4.947 ms**;
- filter destruction-candidate latency: median **4.397 ms**, p95/max
  **6.587 ms**;
- all callback processing: median **3.748 ms**, p95 **46.080 ms**, maximum
  **57.217 ms**;
- POC-issued steady global queries: **0**.

However, request-to-filter-correlation readiness was **3,945.608–4,315.023
ms** (median **4,261.876 ms**), so every cold sample exceeded the fixed
3,000 ms bound. In the same controlled runs, one direct `AXWindowCreated`
callback arrived **4.970–44.283 ms** after the fixture create request, while
the fixture-scoped filter callback arrived **3,944.859–4,314.705 ms** after
it. The direct callback class had processing durations **23.582–57.217 ms**;
with five samples its nearest-rank p95 exceeds the 50 ms steady-callback gate.
These direct timings are controlled-run observations, not alias-based identity
joins.

All five cold exports had exact query counts, zero steady global queries, and
clean observer/fixture shutdown. Legacy 10bucks was restored. The volume does
not establish the required warm count or a passing cold readiness path. It is
narrow evidence that the tested filter correlation path is late on fresh
fixture creation and missed the rapid same-process second creation, while the
direct AX creation signal arrived much earlier and requires further adapter
comparison rather than being accepted as authority from this fixture alone.

### Fixture-only one-sample smoke/calibration — recorded result

**Observed, fixture-only:** one approved warm fixture smoke/calibration sample
completed. All eight expected markers occurred exactly once and in the required
order. The redacted summary reports **52.508 ms** from create request to the
fixture-visible completion, **0.115 ms** for pending work, and **0.419 ms**
from close request to native-close completion.

- Trace schema, marker order/counts, and owner-only `0600` permissions passed.
  Cleanup passed: the fixture socket and process were absent, and the tree was
  clean after the sample.
- The delegated runner initially reported **FAILED** because its ad hoc
  evaluator incorrectly required `elapsed_ticks` on request records and then
  subtracted completion metadata. No app, build, IPC, or Hammerspoon action was
  rerun. The orchestrator instead performed a bounded local review against the
  documented schema: each completion record already stores `elapsed_ticks` for
  its request-to-completion interval, using the timebase frozen by
  `run_started`.
- The one close observation satisfies its fixture-local **<= 1,000 ms**
  one-sample diagnostic limit, and the one pending-work observation satisfies
  its **<= 100 ms maximum** diagnostic limit. The create observation is below
  100 ms only as a diagnostic. With one sample, it establishes neither a warm
  p95 nor any warm-create pass.

This is a successful fixture-only smoke/calibration observation. It is not a
POC-001 pass, does not prove Hammerspoon or representative-app behavior, and
does not satisfy any observer, liveness, readiness, destruction-authority, or
warm-p95 gate.

## Conclusion
Pending. This protocol proves no macOS/Hammerspoon behavior yet.

## Production consequence
Pending result. Until this POC passes, do not freeze the event adapter, use an
event as authoritative destruction, add a safety poll, or begin the control-
plane replacement that depends on lifecycle observation. A failure may justify
a narrower adapter experiment or the least-frequent non-destructive targeted
check; it does not justify treating absence from `_orderedwinids()` or a global
snapshot as death.

## Cleanup
The step-2C POC-only observer is retained for evidence already collected and
for any separately approved future POC-001 run; it is not production code.
There is no currently authorized live operator action. Every future run must
stop the observer, export locally, and restore legacy bindings before legacy
starts. Its isolated traces and any temporary timers/watchers used by later
runs are deleted before a production replacement unless a named reusable
diagnostic has an ongoing owner, a documented use, and measured negligible idle
cost. The standalone fixture implementation handoff in the POC README is POC-only;
its source/test checkpoint and generated build artifact are not production
runtime evidence. Any later fixture and its POC-only artifacts must be removed
unless separately retained under the same gate.
