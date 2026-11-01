# POC-025 — Ended-application retirement at desktop arrival

## Verified scope
On 2026-11-01, investigation of apparent duplicate navigation found a retained
non-Thunderbird member whose owning application no longer resolved. Its identity,
PID, bundle and native leases differed from the live Thunderbird member. Exact AX
returned Messaging failed, not InvalidUIElement. This does not explain the user's
original column jump or prove whether termination delivery was missed or rejected.

Hammerspoon 1.1.1 `hs.application:isRunning()` calls `applicationForPID` on the
stored PID. It is a process-existence check, not a retained-generation guarantee.
A reused PID returning true must retain the old member; nil/errors also retain.
Only explicit false permits this bounded recovery. No window snapshot absence is
used as destruction evidence (STATE-004/005, WIN-005).

## Narrow native proof and acceptance
Reused owned SIP-enabled fixture guest `10bucks-run-ft-eaa07ef31097`; fresh AX
permission granted, Secure Input off, no manager/FT controller at entry. Existing
three ordinary windows excluded from the acceptance candidate and left untouched.
Owned AppKit fixture: retained application running=true while live, running=false
following acknowledged normal quit/exit0; task/timer stopped, no forced termination.

Frozen acceptance used two separate owned fixture processes, one window each,
columns layout. Suppressed only the ending process's original termination and
window-destruction deliveries. After normal quit, its member remained, proving
fault injection. Restored normal delivery, then invoked the existing regular
entry discovery boundary. Candidate removed the ended process's membership,
application record and route, retained the other window, and independently observed
its full-width native frame and actual native focus. No corrective focus/frame
operations were applied by the test after assertions.

First run failed because the test filter also suppressed the new reconciliation
notification. Original failure retained; restoring delivery before reconciliation
repaired only the harness. Product source was unchanged between runs.

Ignored evidence: `.pi/retirement-native-r1.json`, `retirement-native-r2.json`,
`retirement-freeze-r1/`, `retirement-freeze-r2/` (44 hashed source/controller files).
Fixture executable SHA256:
`f79728b31b3b5cb437dcf805d4e2b782ef4cecf47b7674ee6d46318e5eb666e3`.
Result: second run PASS; both quit acknowledged/exit0, mailbox claims absent,
candidate stopped, no captured validity/discovery resource outstanding, timer stopped.
Guest retained three preexisting ordinary windows. No host effects this slice.

## Cost and limits
One pass over retained application records, once per initial regular-desktop entry
discovery, not startup or bounded discovery retries. No new timer/global AX scan.
Thirty paired reads of the two ended retained apps: median0.459ms, p95 0.647ms,
max0.822ms. Hammerspoon logs missing-process diagnostics on these reads. Inclusive
acceptance reconciliation was36.62ms, including reduction/frame/focus/discovery;
not an isolated query latency or host statistical performance certificate.

Acceptance invoked discovery directly, not a native desktop switch. No event trace
excludes late original termination after delivery restoration; synchronous discovery
plus source/pure coverage supports attribution, not callback-order proof. Native
frame readback is not pixel evidence. No full wake/real-app matrix, real missed-callback
reproduction, physical-host latency, or original column-jump proof. PID reuse can defer retirement. Generic
pure regressions cover live/hidden/fullscreen/uncertain/reused-PID retention,
resource/context/generation/subscription reentrancy and full reducer/resource
release. 354 Lua tests pass; independent source review reports no blockers.

## Production consequence
`lib/macos/window_host.lua` checks retained owning applications at the existing
regular arrival discovery boundary. Explicit false publishes through the same
application termination owner as native events; reducer removal commits before
layout/focus effects. Queries are followed by exact-record/generation/context
checks. This fixes the proved ghost lifecycle gap, not semantic window deduplication
or every focus-failure scenario. Host deployment requires separate authority.
