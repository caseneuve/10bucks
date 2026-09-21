# POC-009 — Unchanged native focus confirmation

## Status

Passed as two narrow mechanism observations: one callback-only command remained pending; a separate same-target focus/read probe matched native focus. This does not establish end-to-end command acceptance, callback reliability, or statistical performance compliance.

## Decision enabled

Use one targeted actual-focus read after a requested focus effect. Normalize a matching result through the ordinary focus event path; do not wait exclusively for a callback when focus did not change. A missing, failed, or nonmatching read is not confirmation.

## Hypothesis

Focusing an already-focused window can leave a callback-only managed request pending; a direct post-effect actual-focus read can confirm the unchanged native target without polling.

## Environment

- macOS 26.5, build 25F71, Apple Silicon, built-in display.
- Hammerspoon 1.1.1.
- Repository baseline: `0a76ebd`, branch `dev-engine-rewrite`.
- Sole active runtime: development; 12 hotkeys, zero instrumented production timers.
- No system settings, configuration, installation, or runtime topology changes.

## Procedure and instrumentation

The lead installed temporary, explicitly invoked in-memory wrappers around composition events, Space activation, host startup, app watcher attachment, and application-window enumeration. Rows recorded monotonic timestamps, event types, aggregate durations, and per-run window/Space/application aliases only. An external diagnostic one-shot removed the wrappers after at most 30 seconds; the lead also explicitly removed them after each capture. No production diagnostic or polling loop was installed.

1. On the single-member regular Space, verify native actual focus and Core desired target both name its member, with no local pending request.
2. Invoke `FocusNext` once (the `j` command).
3. Inspect native actual focus, normalized events, and pending state after approximately 3 seconds.
4. Separately request focus on the already-focused native handle and immediately call `hs.window.focusedWindow()` once; compare identities and measure effect/read durations.

Installed source `/Applications/Hammerspoon.app/Contents/Resources/extensions/hs/window.lua`, `objectMT.focus` (line 513 in this installation), implements `becomeMain()` followed by application `_bringtofront()`. It returns the window, not a focus completion acknowledgment. There is no documented promise that unchanged focus produces a callback.

## Acceptance threshold

The targeted read must return the requested native identity without enumeration, a timer, or repeated checks. Nonmatching or absent results must remain unconfirmed. The bounded callback trace must distinguish no delivered confirmation from a matching native observation. This is mechanism evidence, not a delivery reliability or p95 gate.

## Results

**Verified:** the single-member command requested its already-focused member. At 3.3 seconds native focus still matched, but the Core request remained `pending=true`; no normalized focus callback had arrived during the capture.

**Verified:** the separate immediate post-effect query returned that same native identity. Focus call duration was **3.71 ms** and actual-focus query duration **1.94 ms** (`n=1`). No enumeration or timer was required for that observation.

### Related baseline timing, not a focus failure

Two cross-Space previous-window invocations both received target focus callbacks before Space watcher activation; local/global pending cleared correctly in these two samples. Space activation itself blocked for **1217.65 ms** and **313.22 ms**. Host bootstrap consumed **1206.84 ms** and **310.19 ms**, including one `app:allWindows()` call of **328.65 ms**. Thus zero permanent timers does not imply a responsive event path. These measurements attribute baseline blocking to repeated observer/enumeration startup, not a statistical performance pass or authorization to remove discovery.

## Conclusion / production consequence

**Verified:** the observed unchanged-focus request remained pending without a new AX callback; the separate same-target focus/read probe returned a matching actual window.

**Target production consequence:** use a single matching post-effect read as another confirmation boundary, sharing the native focus path between local intents and global previous-window requests. Feed actual observations through normal reduction after the request commits. Never confirm from stale retained per-Space actual state or merely from the return value of `focus()`.

**Deferred:** unmatched/failed focus completion policy, full cross-Space and column acceptance, and 30-warm/5-cold performance certification. The blocking bootstrap is a separate measured defect, not solved by this confirmation change.

## Production acceptance at `69115f6`

The lead independently ran 113 passing Lua tests, parsed all production/test Lua, reviewed the diff, then reloaded only the development Spoon (old runtime stopped before the candidate started). Config/symlink and the stable checkout were unchanged.

**Verified:** 30 synchronous same-target `FocusTarget` commands all returned with local pending cleared. Measured command-processing median/p95/maximum were **8.24/13.71/17.82 ms**. Counters increased by exactly 30 native focus requests and 30 targeted focus reads, with zero frame writes, application bootstrap queries, or ownership queries. These are warm synchronous command-processing samples, not physical-key delivery, next-key service, or cold-path certification.

**Failed next acceptance boundary:** after that reload, externally focusing an owned test window on a previously undiscovered regular Space activated that Space and admitted both of its members. Native actual focus matched the test window, but the new Core's actual and desired IDs remained unset and global history still contained only the other Space's member. Acceptance stopped there. Source inspection confirms bootstrap emits readiness without subsequently sampling actual focus; an early focus event for an undiscovered member cannot establish its managed history. The exact callback order of this failed cold-entry action was not captured; callback-before-Space activation was observed in the earlier traced switches. The failing postcondition and missing post-bootstrap read are verified, while the precise lost-signal ordering remains a hypothesis. This is an implementation observation-boundary failure, not evidence that macOS failed to focus.

A separate pre-fix diagnostic sampled native focus on entry to a normalized focus event: one callback payload named an unmanaged window while the native focused window still matched the managed target. The payload alone was therefore not a valid current global-focus observation in that sample. This does not establish frequency or representative-application reliability.

**Target next increment:** use one actual-focus reader for post-effect confirmation, AX/application focus signals, and observation after bootstrap. It emits the native returned identity through normal reduction, never focus effects during bootstrap, never admission from the focus fact alone, and no event for a failed/nil read. Keep discovery and pending-order policy unchanged.

## Cleanup

All temporary trace wrappers were explicitly restored after capture. Aliased trace exports remain under ignored `.pi/` for local review; no private native identity/title data is included here. The temporary diagnostic is not imported by production. No windows were closed, and no production timer or configuration change was made during this POC.
