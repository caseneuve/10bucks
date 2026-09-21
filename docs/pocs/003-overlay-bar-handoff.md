# POC-003 — Overlay bar and pointer handoff

## Status

**Narrow hover/return and Mission Control observation passed; fullscreen transition flash remains a defect.** This is not complete BAR-* acceptance or a performance certificate.

## Decision enabled

Use an overlay canvas with event-driven content and canvas mouse-entry observation, plus temporary pointer-only tracking while hidden for native-menu handoff. Keep renderer lifetime independent of active window-host replacement. Fullscreen transition visibility still needs a correction and targeted acceptance.

## Hypothesis

An overlay canvas can remain visible without periodic content refresh, hide on pointer entry, and return after pointer exit/grace while allowing use of the native auto-hidden menu bar.

## Environment

- Supported host baseline: macOS 26.5 / build 25F71, Apple Silicon built-in display, Hammerspoon 1.1.1 (recorded in POC-009/010; versions not re-queried for this probe).
- Execution: 2026-09-21, branch `dev-engine-rewrite`, HEAD `699d3ec`.
- Fresh preflight: existing development runtime started, 12 bindings, regular context, no existing probe. Installed link unchanged.
- No settings, runtime configuration, installation, or Space topology mutations requested by the probe.

## Procedure

The human explicitly approved a 60–90 second temporary overlay/hover/Mission Control probe. Lead loaded a standalone 90-second diagnostic, without stopping/reloading the manager or manipulating any application window. The human was asked to enter/leave the top strip and inspect Mission Control. The human also visited existing fullscreen windows and reported a brief flash before disappearance; this was not an automated fullscreen mutation or scripted fullscreen matrix.

Canvas: 32-point strip at configured display full-frame top, `overlay` level, `canJoinAllSpaces`, `stationary`, `ignoresCycle`, non-activating. One initial element replacement. Background element tracks mouse enter/exit; entry hides the canvas. A temporary 50 ms pointer-only timer runs while hidden, and stops when the pointer has remained outside for at least 200 ms and the canvas returns. A Space watcher hides it on observed non-user context and restores it on observed regular context. A 90-second deadline deletes every native resource.

The probe text was fixed, not actual user window content. No native IDs, titles, coordinates, URLs, or raw AX values were exported.

## Instrumentation / threshold

Aggregate counts and relative event timestamps only. Fixed correctness expectations: visible pixels and working native-menu handoff according to human observation, return after exit/grace, no recurring content refresh, no persistent pointer tracker after return, and complete cleanup at 90 seconds. No statistical latency threshold was claimed. `isShowing()` alone is not pixel evidence.

## Results

Human report: “everything works fine,” with one qualification: moving to a fullscreen window caused a fraction-of-a-second flash before disappearance. This supports qualitative hover/return and Mission Control visibility, not all native lifecycle cases.

Lead independently inspected the retained trace:

- One element render, seven shows, six hides, nine event-triggered active-Space/type reads, 129 pointer reads (includes one startup pointer check).
- Three mouse-entry handoffs recorded. The pointer-left-to-return intervals were approximately 248, 251, and 251 ms, consistent with a 200 ms grace sampled by a 50 ms timer. These are diagnostic samples, not p95 or physical-event latency claims.
- Multiple watcher callbacks classified fullscreen; later regular classifications triggered return. The trace contains no native animation/focus timestamps, so it does not prove whether the flash precedes callback arrival, results from callback service delay, or has another native ordering cause.
- Automatic cleanup at approximately 90.004 seconds. Post-run read verified probe inactive and canvas, pointer timer, Space watcher, and deadline references absent.
- Existing manager still started with 12 bindings.

## Conclusion / production consequence

**Verified:** the tested overlay/entry/temporary-tracker mechanism worked qualitatively without recurring content rendering; complete native resource cleanup was observed.

**Hypothesis:** hiding only after the fullscreen Space watcher is serviced is too late to prevent the reported transition flash. Do not label that timing mechanism proved by this trace. Do not add polling, app-name exceptions, or arbitrary transition delays to conceal it.

**Remaining:** fullscreen/tiled transition flash; appearance notification delivery; topology-only update delivery; App Exposé-specific observation; full production rendering/query budgets and lifecycle acceptance. No settings or destructive Space experiments are authorized by this result.

## Implementation-boundary source check

Before implementation, lead inspected installed `hs/spaces.lua`: `activeSpaceOnScreen` and each `spaceType` call take their own `data_managedDisplaySpaces()` snapshot. Repeating `spaceType` for every desktop would multiply native queries merely to derive bar labels.

Reuse POC-001's narrow calibration evidence for one topology snapshot instead. A fresh read-only check on 2026-09-21 at implementation baseline `699d3ec` confirmed the selected display's `Display Identifier` matches the configured UUID, `Spaces` is an ordered array with numeric `ManagedSpaceID` and types 0/4, and `Current Space.ManagedSpaceID` is numeric. Only aggregate shape/count was exported; no native IDs were recorded. This supports deriving current context and regular positions from one snapshot. It does **not** establish delivery of topology-only change notifications or authorize Space mutations.

## Reviewed candidate load and human acceptance

On 2026-09-21 the user explicitly authorized implementing the bar and loading it for manual testing. Lead and independent Sol source review completed; final pure checks were **145 passed, 0 failed**, all production/test Lua parsed, and diff checks passed. The retained-Space regression asserts exactly one correct first frame, not merely a corrected final frame. Source remained uncommitted on base `699d3ec`; a private SHA-256 manifest identifies the loaded candidate.

At approximately 21:15, the lead stopped the previous Spoon before starting the candidate with the same configuration. Installed link and settings were unchanged. Immediate aggregate verification found: started, 12 bindings, previous runtime stopped, regular context, matching explicit display ownership, one 32-point canvas reporting shown, correct minute text, no pending global focus, one clock timer, no pointer tracker, and an allocated appearance watcher. A canvas reporting shown is not proof of pixels; production visual acceptance remains with the human.

A bounded **30-sample warm unchanged-publication** measurement recorded median/p95/maximum **0.220 / 0.606 / 1.117 ms**. Temporary wrappers counted zero element replacements, shows, hides, canvas-frame calls, topology queries, actual-focus reads, running-application enumerations, or pointer reads during these samples. All wrappers were restored before returning. This verifies that repeated unchanged publication did not perform those intercepted operations in this sample. It is **not** changed-content repaint latency, physical-event latency, a cold benchmark, or a full performance pass.

The candidate hides on observed actual fullscreen focus/lifecycle facts as well as confirmed Space context, and publishes committed bar state before native window effects. Whether this eliminates the reported transition flash remains unverified. `AppleInterfaceThemeChangedNotification` is an isolated **Hypothesis** for theme-change delivery; watcher allocation and fake callback tests do not establish native delivery or callback/read ordering. Manual light/dark acceptance is still required.

### Human acceptance

After the candidate was loaded, the human reported **“works fine”** and explicitly authorized the bar commit. This is positive qualitative manual acceptance of the live candidate, not a completed scripted matrix. The report did not separately identify a light/dark toggle or quantify fullscreen transition flicker; those narrow delivery/timing claims and the broader performance gates remain unverified. No extra native action or reload was needed to commit the accepted code.

The human's preferred next parity slice is desktop switching, creation, and deletion, but explicitly requires discussion before implementation or native experiments. This result does not authorize starting Space operations.

## Cleanup

All probe-native resources were automatically removed. The ignored `.pi/bar-handoff-probe.lua` and inactive `tenBarProbe` aggregate trace are lead-owned temporary diagnostics for this slice only, with no production imports or idle activity. Invocation requires explicit approval; rerun is not authorized by the result. Remove the script after the renderer acceptance no longer needs its exact reproduction procedure. No user window was closed or changed.
