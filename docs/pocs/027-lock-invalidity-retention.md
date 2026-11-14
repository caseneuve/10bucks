# POC-027 — Locked-session AX invalidity is not window destruction

## Incident and mechanism
On 2026-11-01 the user reproduced loss of column split/navigation after screen
saver and unlock on D1, following similar D3 failures. Running frozen fa8005d
snapshot retained only one D1 member. Existing aggregate instrumentation captured
an asynchronous validity removal followed by three normalized WindowDestroyed
observations within about11ms; repeated earlier clusters have the same shape.
This supports false validity-based retirement, but aggregates lack per-window and
lock timestamps and cannot prove every prior omission/lag was caused this way.

**Verified narrow platform proof:** owned guest10bucks-run-ft-eaa07ef31097,
Accessibility granted, Secure Input off, no candidate at entry, existing three
windows untouched. Owned ordinary AppKit fixture with retained exact AX resource
and confirmed native regular-Space ownership. Started normal screen saver through
`hs.caffeinate.startScreensaver()`, observed screensaverDidStart/screensDidLock.
For48 samples the retained AX handle reported invalid while the native window
still existed and owning app remained running. Escape stopped guest screen saver;
observed screensaverWillStop/screensaverDidStop/screensDidUnlock. The SAME retained
handle became valid again. Thus InvalidUIElement during lock cannot justify durable
membership removal. No permissions/SIP/settings changes or host screen actions.

## Small correction
Host validity check first requires an unlocked on-console session using existing
`hs.caffeinate.sessionProperties()` fields CGSSessionScreenIsLocked and
kCGSSessionOnConsoleKey; unknown session properties retain. Session is checked
again before removal after the exact-resource query. Native asynchronous invalid
mailbox results use that same current check, not the lock-era worker result alone.
The adapter still forwards real current unlocked invalidity through existing
WindowDestroyed reduction/release. No new session watcher, discovery scan,
restoration queue, or polling owner; projection, grouping and focus are unchanged.

Synchronous reconfirmation is performed only on an invalid worker row, not every
50ms mailbox poll. This fixes destructive lock handling, not every Accessibility
failure, raw native destruction notification, or screen-unlock frame drift.
Pure regressions retain through lock, reject stale invalid result after revive,
and still remove genuinely invalid unlocked resources. Existing tests now model
both worker invalidity and exact-resource invalidity. **361 Lua tests pass**;
whitespace clean. Performance gates were not statistically certified; the rare
invalidity confirmation adds a synchronous query, so slow app invalidity cost
remains a qualification rather than an asserted latency fix.

## Native acceptance
Frozen patched candidate, two owned fixture windows, columns split and B actual
focus before screen saver. Real screen saver/lock, held for1s with retained exact
membership/leases; sampled focused AX invalidity=true. After normal unlock,
independent native frames remained A-left/B-right, exact handles were valid, no
WindowDestroyed count increase, exact manager/host leases unchanged. Direct
FocusLeftGroup then FocusRightGroup independently confirmed native A then B focus.
These commands test focus routing, not physical keyboard delivery or j/k cycling.
No corrective frame/refocus during lock/unlock to manufacture retention success.
First acceptance run passed, no harness repairs in acceptance.

Fixture quit acknowledged/exit0, claims absent, candidate/controller/watcher stopped,
captured validity/discovery resources drained. Independent guest cleanup: original
three windows retained, screen unlocked. Platform POC also quit acknowledged/exit0
and stopped sampling/watcher. Frozen controller/source/fixture identities in ignored
`.pi/unlock-retention-freeze-r1/`, `.pi/unlock-retention-r1.sha256`; results
`.pi/unlock-retention-native-r1.json`, `.pi/unlock-validity-r1.json`; controllers
`.pi/unlock-retention-native.lua`, `.pi/unlock-validity-poc.lua`; host aggregate
`.pi/unlock-event-aggregates.json`. No private user-window contents/native identities
in evidence.

## Authorized host acceptance
User authorized frozen candidate replacement and a normal host screen lock, then
added a second current-desktop window and authorized screen saver repetition.
Independent load checks confirmed exact28 frozen artifacts matching guest acceptance,
26 enabled bindings, full configuration preserved, previous runtime stopped and
validity worker drained. Loader IPC reply timed out; independent ready/source
verification established success without a load retry.

Direct lock/unlock retained all5 baseline managed memberships/exact leases and
coordinator state. The subsequent screen saver test began with two available
current-desktop windows in two columns and8 managed windows across retained scopes.
Observed screensaverStarted→locked→screensaverStopped→unlocked; all8 memberships/
exact leases and coordinator data retained, both current-desktop native frames
unchanged within2points. User reported success. No corrective frame/focus effects,
synthetic keys or desktop switching were applied by the test. These are native
frame readback and user acceptance, not pixel/latency certification. Temporary
host observers/deadlines/settle timers all stopped; host unlocked and sole frozen
patched runtime remains active. Ignored controllers `.pi/host-lock-check.lua` and
`.pi/host-screensaver-check.lua`; primitive baseline resource keys stayed in host
memory and were not exported. Existing focus-recovery/lag qualifications remain.
