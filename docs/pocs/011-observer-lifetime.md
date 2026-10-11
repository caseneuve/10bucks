# POC-011 — Observer lifetime and identity routing

## Status

**The narrow wrapper-equality and independent-watcher pilot passed.** A separate cross-desktop pilot recorded retained title delivery, but failed its overall gate; those qualified observations are not production acceptance. A subsequent candidate passed independent source review (179 tests) and the bounded owned-window inactive-destruction/cleanup sequence below. Sampler completeness and latency gates failed; there is no performance or holistic production acceptance. No PID/window-ID non-reuse guarantee or broad lifecycle pass is claimed.

## Decision scope

Retain the qualified observer/routing proof separately from the failed performance gate; do not treat this canary as production acceptance or a performance waiver. The target is to keep observation alive across desktop activation without using cached discovery as completeness evidence, reject stale callbacks by resource lifetime rather than native lookup ID alone, and retain full activation discovery in the first increment.

## Environment

September 22, 2026; supported macOS 26.5/build 25F71, arm64 built-in display, Hammerspoon 1.1.1. The observations used accepted bar commit `a037817` on `dev-engine-rewrite`, 12 bindings. Subsequent source corrections passed independent review as uncommitted candidate patch `5d313721` (179 tests, 44 Lua parses); this is a source gate only. Those earlier observations used the old runtime. The later candidate canary below used a reviewed sequential replacement, with the old manager stopped first.

## Candidate canary — bounded inactive destruction

**Verified, September 22:** reviewed patch `5d313721` ran as the sole manager. The owned-fixture sequence completed in approximately 24.3 seconds; lead and independent reviewer inspected the underlying fixture rows, primitive routing assertions, and timing trace.

- Exact Host/Windows objects and fixture app/window subscriptions persisted across desktop activation.
- A direct fixture title watcher delivered 69.3 ms after the title request, before the owned close. This is **not** separate native proof of the candidate's title-normalization path.
- One candidate-normalized destruction, matched by the owned window's resource, arrived while its Core was inactive. Before observer release, membership/history/route were removed, no inactive pending focus remained, frame/focus request counts did not increase, and active Core version was unchanged.
- Return reused the retained source Core and observers. Fixture exit was normal (code 0); recorded timer/task/watcher/wrapper cleanup, original desktop/topology, 12 bindings, one bar timer, and no pending focus passed. This is bounded cleanup evidence, not general leak proof.

**Failed performance gates:** only 217/240 key-down and 216/240 key-up samples arrived; the sampler ended at its unchanged overall deadline. Maximum received delay was approximately 1204 ms. Candidate activation callbacks took approximately 1117/404 ms; full discovery took 1057/396 ms, including 311 `allWindows()` calls (maximum single call approximately 142 ms). Received-only percentiles cannot establish release performance. Missing-sample cause remains unresolved; sender completion is not delivery acknowledgement.

The pre-run helper manifest omitted the dynamically loaded fixture controller and sender binary. Independent post-run source/binary inspection supports this qualified reading, but future runs must close that artifact-provenance gap. No rerun, relaxed threshold, or performance waiver follows from this evidence.

## Source evidence

Hammerspoon tag 1.1.1:

- [`extensions/window/libwindow.m`](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/window/libwindow.m): `hs.window` equality uses `CFEqual` on AX element references. `id()` separately returns the window's cached native ID.
- [`extensions/application/libapplication.m`](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/application/libapplication.m): application equality uses `NSRunningApplication.isEqual`.
- [`Hammerspoon/HSuicore.m`](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/Hammerspoon/HSuicore.m): `isRunningWithState` re-resolves `applicationForPID`; despite the installed documentation's instance wording, this implementation is not a process-lifetime discriminator.
- Installed `hs/uielement.lua` maintains PID-keyed native-watcher cleanup and invokes requested destruction callbacks before its automatic stop. App-termination metadata is limited; a current PID token alone cannot associate a delayed native termination with a later process lifetime.

These are source observations, not a native no-reuse promise. The proposed adapter defers conflicting identities rather than treating inequality or snapshot absence as death. Durable lifetime-ID expansion was rejected absent a real consumer requiring it.

## Procedure and fixed thresholds — identity/watcher pilot

Lead-only disposable AppKit application, unique run nonce, one ordinary owned window. Native identity is emitted by the fixture and joined only within its own PID; identifiers and handles stay private. Require exactly one corresponding window in each of two app-local enumerations. Attach two direct title watchers, request one fixture title change, and require both callbacks within 2 seconds. Stop the secondary, request another title change, and require the primary callback within 2 seconds with no secondary callback. Startup setup is checked at 3 seconds; overall pilot deadline 15 seconds. Close only the run-owned fixture through its own command channel. Native callbacks run on the existing Hammerspoon instance, not a second manager.

## Results

### Setup failures while approaching the lock blocker

Two initial pilots failed alias/native identity joining before watcher comparison. Two short setup diagnoses observed an application-role AX wrapper instead of the fixture window. Each custom fixture exited normally, with no remaining process/window resources according to its shutdown and app-absence checks. A separate disposable-Terminal creation attempt could not establish ownership and stopped without closing any window; that possible fixture remains uncertain and must not be disposed from snapshot differences.

The lead subsequently verified `loginwindow` owning both actual focus and frontmost application. This establishes the lock blocker at that check, not retrospectively at every earlier sample. These are invalid setup observations, **not watcher mechanism failures**. No threshold was changed. The accepted production source was restored, all 154 pure tests passed, and the runtime was not reloaded.

### Unlocked wrapper/independent-watcher pilot

After the human unlocked, the lead checked actual focus was present and not `loginwindow`. The same corrected pilot passed:

- One fixture window matched across two app-local reads; window equality true, raw Lua userdata equality false; application equality true for two wrappers of that running process.
- First title change reached primary and secondary at approximately 3015.694/3015.803 ms after pilot start.
- Secondary stopped at 5009.435 ms. The second title change reached only the primary at 5021.753 ms.
- Fixture quit requested at 7011.992 ms; process exited normally at 7027.384 ms, code 0. Separate lead post-run aggregate checks—not the pilot trace alone—verified the fixture app absent, deadline cleared, and no fixture-PID managed members remaining in the existing manager. Those recorded aggregates are retained in `.pi/observer-identity-postcheck-03.json`.

This proves that distinct Lua wrappers for this live window compared equal, and that stopping one of these watchers did not stop the other. It does not establish identity across native ID/PID reuse, representative-app reliability, or cross-Space delivery.

### Cross-desktop pilot — failed overall gate, qualified observations

A separate lead-only pilot retained the fixture's primary title watcher while the existing desktop-switch diagnostic switched away and returned. Each confirmed switch requested one fixture title change. The nested diagnostic required all 240 synthetic key-down/up pairs and had a 20-second deadline. The outer pilot mistakenly asserted nested cleanup after only 17 seconds, before that deadline, and failed before its own title-count assertions. These bounds were not changed after the run.

Lead and independent reviewer inspected the saved traces rather than accepting the failure label as platform evidence:

- Both desktop-switch legs were confirmed. The same direct title watcher delivered exactly once between the away/return markers and once after return.
- One ordinary termination callback compared equal to the retained fixture application wrapper. This does not prove association under PID reuse.
- The fixture exited normally with code 0. Final nested cleanup confirmed return to the source desktop, unchanged topology, restored diagnostic wrappers and released resources.
- The key sampler recorded only 218 downs and 217 ups despite sender completion. Sender exit proves its posting loop completed, not delivery acknowledgement. Its `overall-deadline` result correctly reflects the unmet 240/240 requirement.
- Missing samples remain inconclusive: the trace does not distinguish sender/session-event loss, event-tap suppression or disablement, callback starvation, and diagnostic overhead. Instrumented legacy-manager `_contextChanged` calls took approximately 894/1157 ms; these are not title-delivery latencies or candidate timings. Maximum sampled key delay was approximately 1175 ms. No responsiveness pass is claimed.

The narrow conclusion is that this watcher remained usable during this observed away/return sequence. This is neither an overall pilot pass nor acceptance of the replacement runtime, which was not loaded. Private evidence is retained in `observer-lifetime-mechanism-01.json` and `observer-lifetime-attribution-01.json` under `.pi/`.

## Conclusion / production consequence

Use the resource record captured by a callback to guard its lifetime, not raw userdata pointer identity. Native equality supports idempotent reuse within an observed current lifetime. Unknown/conflicting identities remain deferred. The observed ordinary termination equality and cross-desktop title delivery support only those narrow mechanisms; candidate routing, cleanup and persistent production observer ownership still require acceptance. Pure tests cannot establish native delivery.

Full activation enumeration remains intentionally unchanged. POC-002's single `allWindows()` call exceeding 100 ms remains a performance failure; removing observer allocation alone cannot claim the release service budget met.

## Cleanup / retained diagnostics

Lead-owned ignored helpers under `.pi/` are disposable diagnostics, never imported by production: `observer-fixture.swift`, its built application, `observer-fixture-control.lua`, `observer-identity-pilot.lua`, `observer-lifetime-pilot.lua`, and `observer-terminal-pilot.lua`. Stopped private traces preserve setup failures and the successful pilot. The custom application stopped normally and its native watchers/timers were stopped. The possible unbound Terminal fixture is deliberately untouched pending fresh ownership verification. Existing older private fixtures remain unrelated/untouched. No settings or symlink change or production runtime reload/replacement occurred; temporary diagnostic wrappers were restored.
