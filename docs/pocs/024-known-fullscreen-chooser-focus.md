# Known native-fullscreen chooser focus — TODO0004

## Status / scope

**Verified:** selecting an already-managed, non-hidden, non-minimized native-fullscreen
window through the actual chooser reaches its existing fullscreen Space and confirms
exact native focus. Both retained regular placement and independently admitted
unplaced fullscreen ownership pass scoped fixture-VM acceptance. This replaces only
the fullscreen-selection rejection from POC021/022; historical results are unchanged.

**Deferred:** cold-start fullscreen/minimized discovery completeness (TODO0003),
unhide/unminimize, fullscreen toggle/spawn effects, native race/stress coverage and
host/release certification. No host load or host window/Space action occurred.

## Implementation and boundaries

The existing composition-global managed-focus request, FocusHistory reducer,
HandleRegistry and Host focus/observation path remain the only owners. Selection
revalidates the returned resource lease/current application resource and exact AX
validity, then positively reads targeted native ownership and fullscreen property
before focus. Unplaced targets must still have their recorded fullscreen owner;
saved regular placement may differ from the confirmed fullscreen owner. Uncertainty
rejects effects without removing membership or inventing a regular slot.

The request commits before effects. Fullscreen uses one direct exact-handle focus;
redundant saved-Core focus intents are filtered at the existing boundary. Matching
native observations alone update history/clear pending, including unchanged-focus
post-effect reads. Latest explicit targets suppress stale selection/history changes.
An unconfirmed explicit global request expires after five seconds, cancels authority,
observes actual focus without retrying, and reports actionable failure. Replacement,
confirmation and shutdown retire its timer. Terminal native failures propagate through
same-Space batch execution too. This is not a new expiry guarantee for every local
navigation request: local supersession retires the explicit request's timeout.

Unplaced hidden/minimized flags are independently reduced and refreshed on readiness.
Those restoration selections remain rejected, now with actionable UI wording. Existing
structural-operation restrictions remain; fullscreen departure is blocked during
pending desktop creation even with saved placement in the active regular Core.
No discovery scan, polling, restoration/toggle effect, registry or app-specific branch
was added.

## Native procedure / environment

Coordinator alone operated the persistent owned SIP-enabled Tart guest
`10bucks-run-ft-eaa07ef31097`: macOS26.6.2/25G83, HS1.1.1, one1024x768 logical
display, Accessibility/unlocked console, existing three regular desktops, Dock-hidden
Hammerspoon chooser prerequisite. Each runner freezes/hashes the Spoon/native binary,
fixture and helpers; execution deadline95s. Gates unchanged:5s eventual,250ms matching
stability,150ms observation freshness,2pt geometry. AppKit key/active facts joined to
exact held fixture identity/frontmost PID prove focus; native active Space proves
context. No corrective focus after selection. Generic fixture setup changes occur
before their corresponding assertions, not as repairs to failed outcomes.

Root evidence: `vm/results/10bucks-run-ft-eaa07ef31097/`.

- **Unplaced** `session-496a93930d6e`: create/fullscreen A before starting runtime,
  independently confirm fullscreen readiness, then regular D1/C setup. Open actual
  chooser on C and Enter A; assert exact A/F1, pending clear, fullscreen preserved.
  Repeat unchanged target. Exact resource/route/unplaced joins plus every Core's
  window map and regular order assert no fabricated placement.7actions/99samples.
- **Placed + controls** `session-3b851b888368`: native fullscreen retained A, leave F1
  by ordinary desktop shortcut, real chooser Enter returns A/F1; repeat unchanged.
  Compare saved D1[A,C]/D2[D] orders and all retained stack/columns records before
  selection and after confirmation. Native exit restores regular geometry. Existing
  minimized/hidden rejection, exclusion, ranked rows, regular focus and close controls
  remain.55actions/611samples.
- **Preserved failure** `session-981808e51742`: zero trace/selection actions;
  `fullscreenSetup`, frozen `guest.lua:1369` asserted `regular_space_required` despite
  intentionally starting fullscreen. Independent source/raw review classifies this
  as harness setup failure, not native focus failure. Scoped setup assertion repaired
  in a separate run. Transport message-port errors also retained, not substituted
  for the controller failure. No failed artifact was overwritten or relabeled.

All successful traces have zero drops/controller failures. Independent review verified
102/102 manifest files per run, identical successful production manifests/current
runtime+harness, replayed exact native outcome predicates and retained-order/no-slot
checks. All three runs cleaned candidate, chooser native window/default references,
observers/wrappers/timers, validity worker drain and normal unforced fixture task exit.
Fresh coordinator post-check:controller stopped/task absent/pending false, worker drained,
zero ordinary fixture windows. Persistent VM deliberately remains running.
Runner `pass/scenarioPassed=true` but `acceptance=false` for debug reuse: these are
scoped fixture-VM functional results, not broader runner release/host acceptance.

## Scoped measurements (not latency certification)

Selection callback entry→return, excluding eventual animation/confirmation:

| Sample | Processing ms | Focus / targeted focus / ownership reads | Frame requests / writes |
|---|---:|---:|---:|
| Unplaced cross-Space |36.353|1 /1 /1|0 /0|
| Unplaced unchanged |4.121|1 /1 /1|0 /0|
| Placed cross-Space |37.266|1 /1 /1|2 /2|
| Placed unchanged |4.419|1 /1 /1|0 /0|

Placed cross-Space legitimately synchronizes regular survivors; aggregate counters do
not identify recipients. No tiled frames **to F** is source/projection and pure guarded
fixture evidence, not a per-recipient native trace. Hidden/minimized rejection deltas
are zero focus/frame/ownership effects. The wrapper's `applicationWindowQueries=0`
field is not the Host bootstrap/discovery counter: no enumeration claim follows from
that field. The narrow focus implementation itself contains no enumeration.

Two benign keys posted immediately after Enter were received in58.674/28.279ms.
These are n=2 queued synthetic service observations, not independently timed arrivals
during blocking work, physical input, p95 or supported-host budgets. The first exceeds
50ms; it remains recorded. No statistical performance claim or threshold relaxation.
Existing local Core execution prechecks validity then focus checks it again; the direct
fullscreen path uses a single validity read. No universal single-query claim.

## Pure/source checks and review

Coordinator final checks: **345 Lua tests passed;74 Python oracle tests passed**;
changed Lua parses and `git diff --check` pass. New generic sequences cite CHOOSE,
FOCUS, FS, STATE and CMD invariants: placed/unplaced, exact owner/lease rejection,
independent lifecycle flags/readiness refresh, one focus effect/no F frames,
commit-before-effect, unchanged and delayed confirmation, newer targets/stale callbacks,
structural blocking, terminal failure/expiry and shutdown. These prove policy/effect
budgets, not native race success. Python mutations reject wrong actual focus/Space,
fullscreen mode and pending authority. Independent source/raw/simplicity review:
`.pi/todo0004-final-review.md`, no remaining blocker; no new framework or wider suite
required. Pure/doc-only final edits do not change the executed candidate.
