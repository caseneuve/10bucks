# Real Ghostty close regression and unresolved host observation boundary

## Status

**Same-process guest regression PASS; host silent-close repair BLOCKED.**
2026-10-11. Do not describe guest success as fixing the reported host failure.

## Host failure and authority limit

User reported columns with left/right survivors, right focused → create Ghostty
terminal on right → Ctrl+D: underlying right did not gain focus, bar remained2/2;
j/k repaired it. Frozen host candidate1531e42 trace retained240rows/254dropped.
Closed aliases6/7 normalized only within FocusLeftGroup/FocusNext effect boundaries;
alias8 normalized on later context change while its scope was inactive. No raw
window-destruction counts were recorded; source confirms counters are not filtered.
This supports missing delivery to that production callback, but cannot distinguish
registration failure, detachment or platform silence. Actual close times and app
main/UI-element signals were not recorded. Candidate stopped before full host reload;
legacy26bindings/filter/reconcile/workspace/barTimer verified restored. No host user
window creation/closure was automated.

POC-012 already records two exact host resources with explicit destruction
registration, zero destruction callbacks and retained AX validity false. A stronger
registration API alone is therefore not a demonstrated cure. Hammerspoon1.1.1
HSuicore watcher start ignores AXObserverAddNotification results; checked explicit
registration is a valid generic observability/correctness improvement, not proof
of silent-close recovery.

## Owned guest setup

Same running debug guest, no reboot: macOS26.6.2/25G83, Apple Silicon Tart,
HS1.1.1/SIP/AX enabled, unlocked/noSecureInput, one1024×768 logical display,
menu auto-hide on/MRU off. Host legacy untouched.

Transferred host-installed public Ghostty1.3.1 as a ZIP archive preserving signed
framework symlinks. Initial direct shared-directory copy broke framework symlinks
and showed a damaged-app dialog; this was harness setup failure. Failed guest app
preserved separately; exact stale Cancel pressed after valid archive install.
No Gatekeeper/SIP bypass, signature change or TCC database edit. Strict codesign
verification and spctl accepted/Notarized Developer ID observed. First-launch
update choice was inspected and exact “Don’t Check” pressed in the owned guest;
SUEnableAutomaticChecks0/SUHasLaunchedBefore1 verified.

Runner requires installed Ghostty1.3.1 expected bundle, records executableSHA256,
strict signature verification/notarization assessment and effective argv before
launch. Owned launch argv: window-save-state=never, initial-window=true,
command=/bin/zsh -f, confirm-close-surface=false. Last flag is documented and
avoids a quit-confirmation dialog during normal owned cleanup; no host config edit.

## Native scenario

```sh
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-close-recovery
```

All A/B/C are real windows in the **same Ghostty process**, not an AppKit survivor
plus one terminal. A starts from owned app launch; B/C use real Cmd+N with exact
preceding global native focus checks. Joins require precisely one new standard
native resource by equality difference; all previously joined resources remain
present. A full-width → Aleft/Bright → Cright stacked over B → real Ctrl+D on exact
focused C → retained CAXfalse/removal → native Bfocus, unchanged [A]|[B] groups,
order/selections. No j/k, corrective focus or reducer command after close.

Unchanged gates:5s/checkpoint,250ms sampled stability,50ms sampling,150ms freshness/
matching-window gaps,2logical-point frame tolerance. Native frame/focus/invalidity
are independent of cached candidate diagnostics. Fixture task remains zero-window
and participates in independently acknowledged normal cleanup.

Final same-app evidence `vm/results/10bucks-run-ft-eaa07ef31097/session-aa4f3c814f1a/`:
independent high reviewer verifies53frozen hashes,58trace samples/36assertions/
6checkpoints; minmatching250.99ms/maxacquisition21.62ms. Full trace has458.68ms
action-time sampling gap; matching checkpoint suffixes pass. Not uninterrupted
sampling/performance evidence. Ghostty/launcher/fixture normal exit, no force,
observers/timer stopped, claims absent, no pending task/action. VM retained
running intentionally; cold acceptance:false. Prior combined layout/order scenario
also passes on updated source in `session-7004654fadb7`.

## Separate source correction

Guest admission failure `bac0033dc6b4` exposed Bownership unknown and no retry,
with same-scope frame-height refresh nearby. Independent production composition
reproduction proves Host:setContext unconditionally cancelled creation tokens on
geometry-only refresh. Exact live cancellation is not directly traced. Replacement
preserves/rebinds pending tokens across unchanged display/regularSpace/Space-type
without resetting budget/timer; real scope/fullscreen changes still cancel.
Failing-before composition regression, repeated-refresh budget and scope-change
query tests now pass:229Lua/25Python, syntax/diff clean. This fixes that proven
source gap, not host silent-close detection.

## Retained harness failures

- `13efcd1f562c`: Ghostty zero-window baseline kept phaseghosttyBaseline and
  repeatedly bootstrapped; original cleanup incomplete. Correct phase transition
  prevents repeat bootstrap; inspected exact leftover fixture process terminated.
- `b076927c9664`: mixed-app pass is qualified and not evidence for same-app bug.
- `039ee3490708`: same-app scenario passed but Ghostty quit confirmation prevented
  cleanup; result remains FAIL. Inspected exact-owned QuitGhostty dialog closed;
  subsequent argv override allows normal teardown. No retrospective green claim.
- Original host/POC failures remain preserved. Guest probe received appfocus/Main/UI
  plus standard/explicit destruction and CAXfalse; this is not a host silent-gap
  reproduction.

## Architectural blocker / concrete next decision

There is no justified host behavioral fix yet. Snapshot absence cannot authorize
removal. Permanent polling cannot be introduced without selected live evidence
and cost/detection measurements. Expanding events is also not proved by guest
notifications when host delivery is unknown.

One finite exact-resource **host** signal observation is required on the reported
same-process topology: checked app/window registration inventory/running state;
raw-before-guard focused/main/UI-element/destruction; exact target invalidity and
actual global focus before any navigation/Space repair. A delivered alternate
signal permits an event-triggered targeted-invalidity boundary. Silence despite
checked registration requires a deliberately measured narrowly scoped safety
tracker decision. Lead does not have authority to automate creation/closure of
host user windows; coordinate the human-paced sequence or explicitly authorize
an exclusively owned host test-app instance first. Legacy remains active.
