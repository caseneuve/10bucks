# Asynchronous exact-resource AX validity

## Status

**Narrow worker POC PASS; focused safety candidate implemented and guest-accepted.**
Host manual acceptance pending. Prior synchronous cost failure remains unchanged.
No claim of background-close completeness or fallback-first/unknown-read repair.

## Decision enabled

POC012 and repeated checked host traces prove narrow silent destruction with
retained AX invalidity. POC016 rejects synchronous periodic AX reads by fixed
tail-cost gates. This experiment tests the smallest off-main AX query seam,
not a global native manager rewrite or snapshot-based liveness.

## Platform/API basis

HS1.1.1 axuielement common.h/pushAXUIElement stores an AXUIElementRef pointer in
pointer-sized userdata tagged hs.axuielement. The bridge checks tag/size/type and
CFRetains the exact resource; no PID/native-ID reconstruction. Official
ApplicationServices AXUIElementCopyAttributeValue(AXRole) supplies retained values;
only kAXErrorInvalidUIElement (-25202) means ended resource. Other errors retain
uncertainty. Worker-thread operation itself was the live hypothesis.

Serial dispatch source queries at100ms, exports only token/AXError/status/query
start+duration through a64-row mutex mailbox. Lua is never touched on worker.
Generation changes discard in-flight stale results. Main set/poll never query AX.
Public dladdr/dlopen(RTLD_NODELETE) pins the image so hs.reload cannot unload code
beneath an in-flight query/cancel handler. Process-lifetime image retention is
intentional and documented, not unloading/leak-free evidence. Worker CF/context
references release after cancel handler; stop is nonblocking, drain is separate.

## Environment and fixed gates

Same running exclusively owned debug guest, no reboot. macOS26.6.2/25G83,
AppleSilicon, HS1.1.1, SIP/AX enabled, unlocked/noSecureInput; signed notarized
Ghostty1.3.1. Host legacy untouched. Native binary/source/driver/analyzer frozen.

Gates before execution:≥30validnative samples;≥30set andpoll costs separately,
median/p95≤1ms/max≤5ms; exactly100posted keydowns+100ups with actual callback
receipt p95≤50ms/max≤100ms; realCtrlD exactB firstpostclose invalid acquisition,
completion and delivery≤250ms; zero dropped/stale rows; in-flight replacement and
stop suppress results, oldquery complete before rearm, drainack and normalcleanup.
Nearest-rank percentiles. Controlled200ms worker hold is cancellation testing only,
excluded from nativequery latency. No threshold relaxation.

## POC results

Ignored `vm/results/10bucks-run-ft-eaa07ef31097/async-poc-r2/`:
independent reviewer checks5hashes/rawclocks,30validrows then exactinvalid:

- set p95/max0.000791/0.003375ms;
- poll p95/max0.007208/0.044416ms;
-100down+100up callbacks, no loss; receipt p95/max11.013/24.140ms;
- CtrlD→acquisition/completion/delivery90.666/90.970/96.456ms;
- zero stale/dropped results; controlledinflight replace completed without result;
  stop followed by drain acknowledgment; normal app/launcher/binding/timer cleanup.

First frozen `async-poc-20261011` failed input delivery:100F18posts/0callbacks,
48validAXrows; normalcleanup. Independent inspection finds no AX failure, and
F18-specific cause unproved. Ordinary HyperY calibration passes before measurement;
key substitution is harness repair, not threshold relaxation. Original retained.

## Production replacement

`10bucks.spoon/native/ax_validity.m` derives one production worker from proved seam,
without testdelay. `native/build.sh` compiles arm64 using installedLuaSkin headers;
binary ignored, built before runtime load and hashed in frozen acceptance snapshots.
`lib/macos/ax_validity.lua` loads it lazily; missing build fails, no synchronous fallback.
One Host-owned serial worker is reused across focus changes. Target is exact focused
managed regular window plus lease/appresource/scope/generation;100msnativequery,
50msprimitive mailbox drain. Explicitinvalidity submits lease-bound destruction
through Windows→reducer; state commits before recovery effects. Unknown/errors retain.
Target clears on unmanaged/no focus/minimize/hide/fullscreen/scopechange/shutdown.
Same-scopegeometry refresh rebinds authority without resetting budget. No app-specific
policy, global enumeration or nativeID liveness. Poll/setup/teardown errors contained;
setup reentrancy rechecks authority. Final stop/drain distinct. This is measured,
scoped active safety observation, not a zero-query idle claim.

New composition tests use explicit ephemeral worker injection (no globalno-op mock):
mailbox invalidity traverses actualHost/Windows/Core removing membership/history/routes,
recovering occupied column and normalizing empty column to A|B with nativefakeBfocus.
233Lua tests pass; fault tests cover factory/set/timer reentry, poll/teardown errors,
stale lease/scope/focus/unavailable results and singleworker reuse.

## Native candidate acceptance

Same-guest exact realGhostty scenarios,64frozenhashes each independently verified:

| Session | Case | Assertions/checkpoints | Minimum stability |
|---|---|---|---|
|83584435603f|occupiedclose|37/6|250.35ms|
|7a509631a364|normalization|84/13|250.94ms|
|6e605abbe623|retention|146/23|250.01ms|

Occupiedclose48samples showlivefocusedtarget/nativeworker/mailbox. Sample49 CAXinvalid
stillmanaged; sample50async counter0→1 pairedCremoval/groupsA|B/nativeBfocus,97.76msafter
CtrlD. NativeBfocus already observed atsample49: proves asyncremoval integration,
not solecausation offocus. Other2cases are regressioncoverage (asynccounter0).
Allworkersdrained afterstop,normalunforcedapp/fixturecleanup, no observeddrops.
Action-time sampling gaps764/561/605ms remainqualified; matchingcheckpointwindows pass,
not whole-transition/performancecertification. Reused coldacceptance:false.

## Remaining limits / cleanup

Fallback focus arriving before invalidity while synchronous validity is unknown cancels
former target; its later result is stale. This sequence remains unresolved/non-destructive;
no broadFOCUS004 waiver. Backgroundsilent closes outsidefocusedseam unaccepted.
Hostfailingtopology must be manually accepted before claiminghostfix.

POCnative source/driver/analyzer under functional-tests/native-ax remains named,
lead-owned diagnostic for worker/cancellation/reload evidence only; no productionimports
and no idlecost. Production has no testdelay or selectable alternative worker.
Hostlegacy restored before source edits, guestcandidate/appstopped, VM remainsrunning.
