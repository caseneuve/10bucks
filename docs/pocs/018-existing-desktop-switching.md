# Existing desktop switching — composed VM acceptance

## Status

**Verified:** composed existing-desktop switching accepted in the owned SIP-enabled
VM; ready for an explicitly requested host manual candidate. Not full host/release
performance acceptance or atomic Mission Control ownership proof.

## Scope and implementation

SPACE-001/002/004/005, STATE-001/002/003, WIN-002, LAY-001/003 and COL-008.
One workspace reducer commits native topology/history/desired intent before one
serialized adapter operation. Positions1–9 focus existing regular Spaces;0 toggles
confirmed previous;N/P navigate cyclically from pending desired. No creation,
manager deletion or move-to-desktop command. Retained Cores keep layout/order/ratio.
Global/local focus cancellation, outer delivery/effect buffering and reducer-owned
orphan retention reconcile removed scopes without declaring windows dead.

The adapter derives from POC002: open MC, yield0.3s, readiness retries50ms≤2s,
one AXPress, native confirmation≤5s. Nil/error press is ambiguous, never retried.
Successful selection pairs Escape events targeted **only to the retained Dock app**
in the same callback after current authority/group checks; no global or delayed
Escape cleanup. Confirmation additionally requires MC absent. Previous dismissal
boundary debt gates the next opening. Dock destruction notification triggers one
fresh topology snapshot; no production topology polling. Dock replacement reattaches
that observer. It is a reconciliation trigger, not window liveness or OS-effect drain.

**Verified narrow fullscreen mechanism:** MC opening from a fullscreen source
changes observed native context to a regular Space before AXPress (open-only trace:
265.6ms). A correlated reducer event retains the initiating tuple and commits a
separate press context, guarded by owned opening/session and unchanged topology.
Ordinary external activation cannot acquire that exemption.

## Environment/procedure

2026-10-12; persistent owned debug guest, macOS26.6.2/25G83, Apple Silicon,
HS1.1.1, SIP/AX enabled; single observed guest display1024×768 logical points.
Three regular desktops prepared once as **test setup**, not product creation.
Each runner invocation freezes Spoon/nativeworker/helpers/scenario/fixture and
manifest. No candidate loaded on host during development. Candidate/fixture stops,
worker drains; debug VM retained. Reuse is explicitly not cold isolation.

Complete authoritative `functional-tests/scenarios/desktop_switching.py` runs real
hotkeys and independently samples native identity/focus/geometry; intent/cache/bar
are secondary diagnostics. Fixed5s completion,250ms matching,50ms samples,
150ms freshness and2pt geometry gates unchanged. Cases: ABC admission, retained
columns/stack/order/selections/0.55ratio, numbered switch/return, both wraps, missing9
no creation, repeated0/toggle, n,n, n,p and absolute replacement while queued.

## Results / independently reviewed evidence

- Primary final regular scenario `session-a802e59ed8fa`: PASS.
- Earlier reviewed regular `session-36a2b6807530`:69/69 frozen hashes,254 assertions,
  19actions,13 serialized confirmed native legs, zero dropped trace rows and normal
  cleanup. First green `session-b6a98c69df60` retained separately.
- Fullscreen subcase `session-1d5d589da030`: PASS. Exact native fixture fullscreen
  source→regular2→regular1, retained unavailable saved slot; exit confirms native
  ownership/frame/availability. Fullscreen lies after regular Spaces in this run;
  arbitrary interleaved/tiled AX indexing remains unaccepted.
- Real Ghostty layout-retention regression `session-0ad25a1f6994`: PASS.
- Guest Dock-boundary probe: inactive create/remove reflected native topology counts
  3→4→3 without a Space-watcher event; composed snapshots agree. Populated removal
  and reorder/movement native flows remain narrower acceptance gaps; pure sequences
  cover retained orphan/late readiness/exact destruction/fullscreen saved-source.
- Source checks:262Lua/36Python pass; diff/syntax checks pass. Independent source
  review resolved reentrant flush, failure recovery, fullscreen routing and native
  revocation defects; no residual High/Medium findings in final source delta.

Private traces/source helpers remain in ignored `.pi/poc/` and `vm/results/`;
all report fields alias native identities and exclude private contents.

## Measurements and qualifications

Three10sample warm batches and five first-switch cold-runtime batches:30warm/5cold,
all complete, frozen manifests verified. Warm/cold posted→requestp95
30.99/25.58ms; benign callback max31.74/18.18ms. These in-process posts do not prove
service of input arriving while the Lua loop is blocked. Cold means runtime, not OS.

Independent C sender r3 posted100ordinary Y events while six switches ran;100actual
hotkey callbacks, senderexit0, zero negative/over50/over100ms rows. Nearest-rank
median0.572ms/p9515.502ms/max25.625ms; source restored/operation settled and empty
keyboard flags. Independent reviewer checked all raw clock/count rows. Narrow guest
service evidence, not physical-host/representative slow-app or exact phase coverage.

Failures retained, not reclassified as passes:
- Initial empty-desktop selection left MC open; return failed. Toggle-based closure
  did not reliably dismiss it. Dock-targeted Escape selected after live evidence.
- FT synthetic Hyper events left modifier flags held; explicit synthetic releases
  repaired the harness, not performance thresholds.
- Late prior Dock destruction cancelled a new leg; dismissal-debt sequencing fixed.
- One changed run had340ms sampling gap; unchanged freshness gate correctly failed.
- Independent sender r1/r2 received99/100; incomplete/censored calibration evidence.
  R3 delayed arming; all100callbacks and sender exit were recorded before fixed
  teardown. Originals kept.
- Fullscreen initial rebase mismatch and original exit-focus assertion failures kept.
  Exit geometry/slot scope deliberately excludes automatic focus restoration (roadmap
  step5); new frozen subcase passed, old failed artifacts remain failed.

**Remaining qualifications:** same-callback group/authority checks are not an atomic
UI-lifetime guarantee against concurrent physical dismiss/reopen. Never infer native
operation drain from cancelling callbacks. Stop/failure leaves ambiguous MC untouched
and exposes manual-dismiss guidance. Supported-host latency and broad real-app
reliability still need manual dogfood/acceptance; guest green does not certify them.

## Manual-feedback correction — fullscreen departure history

User accepted normal host switching and revised SPACE-005: D2→D1→fullscreen must
make previous=D1, not D2. Fullscreen remains unnumbered; cyclic next still anchors
D1. The reducer retains the earlier other regular desktop as a primitive backup;
confirmed return to D1 restores D2 for the next toggle. Repeated fullscreen facts
and correlated MC presentation rebases do not settle that history early.

Authoritative updated fullscreen sequence `session-88a792442e5c`: PASS,
independent review69/69hashes,122assertions/8actions/5serializedconfirmedlegs;
two actual0callbacks before press produce one fullscreen→D1 leg, then0targetsD2.
Normal cleanup/observerstop/workerdrain/zero drops; reused guest qualified.
Regular regression `session-ca8ab12c84aa`: PASS.265Lua/36Python pass.

Prior `session-9fba6e38af68` remains overallFAIL/scenarioPassed=true: candidate stop
failed during cleanup. Original exception was not captured, cause unknown;
subsequent explicit stop succeeded but does not repair that result. Harness now
retains the actual future stop exception without changing cleanup acceptance.

## Cleanup

Production has one adapter path; no gotoSpace busy wait or permanent topology poll.
POC helpers are coordinator-owned ignored diagnostics, no production imports/idle
activity. Guest test modifiers released, nativeworker drained, candidate/fixture
normal cleanup. Host deployment uses a frozen artifact set and sole-manager handoff
with report-preserving legacy reload rollback; memory-only layout state resets.
