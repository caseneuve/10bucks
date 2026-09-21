# POC-010 — Pre-existing fullscreen focus history

## Status

**Passed: narrow native observation and reproduced history omission.** Candidate runtime acceptance is pending; this is not a fullscreen-effects or latency certification.

## Decision enabled

Track independently eligible native-fullscreen windows without fabricating regular layout membership. Distinguish fullscreen-locked AX position from ordinary-window ineligibility. Keep focus observation separate from readiness.

## Hypothesis

A pre-existing ordinary native-fullscreen window can be focused and report confirmed fullscreen ownership while being absent from the regular-only manager/history. Its AX position may be locked in fullscreen.

## Environment

- macOS 26.5, build 25F71; arm64; configured built-in display.
- Hammerspoon 1.1.1.
- Baseline runtime `583f4af`, branch `dev-engine-rewrite`; development Spoon alone.
- Supported settings remain those in `docs/macos-settings.md`; none changed.
- One existing ordinary application window, aliased F; no application-specific production policy. Application-version matrix not measured.

## Procedure and instrumentation

1. Read the application's focused native window, its fullscreen property, owner Space types, generic eligibility fields, and existing registry/Core/history membership. Do not change window mode or geometry.
2. Install the explicit lead-owned aliased focus trace with automatic 30-second cleanup.
3. Focus that existing fullscreen handle. Plan one previous-window invocation only after confirming setup.
4. Inspect the trace before interpreting a failed setup assertion. A human previous-window command occurred at +2.11 s, before the planned scripted invocation; the script assertion therefore stopped and its injected key did not run.
5. Independently verify that the saved target maps to trace alias w4. The trace stores no native IDs, titles, URLs, or messages.

Private diagnostic: `.pi/focus-trace-fullscreen-setup.json`; temporary helper `.pi/focus-trace.lua` is never imported by production.

## Acceptance threshold

The narrow premise requires a standard, nonmodal, resizable foreign native-fullscreen window with one fullscreen owner and a direct trace showing actual focus on it while global managed history omits it. No latency pass threshold is claimed for this diagnostic.

## Results

**Verified:** F reported native fullscreen, one owner of type fullscreen, standard window role/subrole, nonmodal, resizable, and AX position not settable. F was absent from Core membership, the handle registry, and managed global history.

**Verified trace:** baseline history `[w1,w2,w3]`; actual focus then became w4, with matching current-native-focus observations at approximately 36–77 ms. History remained `[w1,w2,w3]`. At +2110.90 ms a previous command requested w2 rather than the immediately preceding regular window w3. Confirming observations for w2 arrived at approximately 2554–2584 ms. The command body took 19.38 ms; this isolated trace duration is not a performance gate.

The failed later setup assertion was operator/procedure interference, **not** evidence that native `window:focus()` failed. No second live action was run to reinterpret that failure.

Existing evidence is reused: POC-009 proves the shared actual-focus read and unchanged-focus confirmation boundary. POC-001's **Fullscreen calibration 003** records resize/property false followed by regular ownership on exit, including a preceding Space callback still reporting fullscreen. Its failed historical latency threshold remains failed; its narrow event-order evidence is not a broad pass.

## Production consequence

- A targeted ownership/readiness result may register an unplaced fullscreen target; only subsequent confirmed actual focus updates MRU.
- Both fullscreen ownership and a true native-fullscreen property are required for the generic locked-position allowance. Ordinary immovable windows remain excluded.
- Existing placed fullscreen windows retain their source Core and exact slot; entry must not request recovery focus behind fullscreen.
- Unplaced targets retain the original management decision. Confirmed regular readiness promotes them without inserting/reordering history; uncertain ownership remains unplaced.
- Reattach known unplaced observers on active-host replacement and reconcile an exit from the initial native property. No polling, destructive snapshot reconciliation, global scan, or app-specific exception.

## Candidate checks / remaining scope

Current pure suite: **133 passed, 0 failed**, including fullscreen↔regular previous, pending confirmation, newer-local-request supersession, startup with no regular Core, exit promotion, and removal. Lua syntax and diff checks pass. Independent review found no code blocker but requires live evidence for observer reattachment and missed-exit reconciliation. Native acceptance is not complete.

**Blocked live preparation:** a fresh disposable Terminal fixture C was created after an app-local zero-window baseline and a sole-new-window delta. Two setup checks could not establish actual focus. Independent inspection found `com.apple.loginwindow` owning native focus. Both checks aborted before stopping 10bucks or requesting a fullscreen mutation; all phase/failsafe timers stopped. This is a locked-session setup failure, not evidence against native focus or reattachment. The old runtime remains loaded. Resume only after unlock and fresh ownership/focus verification. Configured fullscreen-on-create, fullscreen effect timeouts, source-Space removal, and broad lifecycle/performance certification remain deferred.

## Cleanup

Trace wrappers and the temporary timer were stopped/restored. No existing user window was closed or toggled fullscreen; no explicit geometry mutation was requested. At 18:20 on 2026-09-21 the user explicitly requested loading the candidate before the outstanding live check. The old runtime was stopped, all changed module caches replaced, and candidate startup succeeded with 12 bindings and zero production timers. A read-only check confirmed native/Core actual/desired/global-history alignment with no pending requests. This establishes loading and initial regular focus alignment, not fullscreen acceptance. Owned fixture C remains, guarded by one passive lead-owned destruction watcher; its private ledger is `.pi/owned-fullscreen.json` (0600). It is retained solely for the blocked live check and must be cleaned up afterward. Old A/B targeted lookups no longer resolve; this is not disposal authority. Freshly verify ownership before any use or cleanup.
