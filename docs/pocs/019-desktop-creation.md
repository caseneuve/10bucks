# Desktop creation — asynchronous composition and VM evidence

## Status

**Verified:** one explicit create command implemented through the existing workspace
reducer/Spaces adapter; native guest regular/fullscreen/race cases and relevant
measurements recorded. Independent source/native reviews completed; reviewed VM checkpoint ready for a separately authorized manual host trial. Not physical
host acceptance, complete release performance or atomic native-mutation attribution.

## Decision / API basis

SPACE-003/CMD-006 creation extends the single runtime, not legacy code. Installed
HS1.1.1 `addSpaceToScreen` opens Mission Control, resolves `mc.spaces.add`, AXPresses,
and optionally closes. Its subgroup helper spins up to2s and returns no new identity;
production must not call it unchanged. Reuse POC002/018 timer-yielding selection and
fullscreen presentation rebase; nativeworker unchanged.

Frozen owned-guest mechanism probe observed one add AXPress append one regular ID,
old order unchanged, active source unchanged/MC still open. One selection of actual
new ID plus retained-Dock Escape produced actual destination and MC absence. Add/
select calls3.603/.365ms in one sample—not statistical performance. Competing-add
probe observed two new identities and refused selection; failed singleidentity gate
retained. No claim AXPress receipt identifies a causally created Space atomically.

## Implementation / fixed procedure

One reducer generation covers requested→adding→selecting→pressed. Reducer commits
before add and selection; adapter keeps ephemeral AX/timers. At most one add attempt,
including ambiguous errors. Operation-bounded50ms native reads discover inactive
creation while MC remains open; no permanent topology poll. A compatible one-ID
append with unchanged initiating/rebased source becomes selection authority; changed
order/types/source or multiple additions revoke it. Creation selection full/regular
order must remain unchanged through confirmation. This is compatibility evidence,
not proof against an indistinguishable external single addition after failed add.
Native actual topology always reconciles; failure never deletes or rolls it back.

Initial readiness≤2s, .3s yield,50ms retries; selection readiness gets≤2s capped by
original5s operation deadline. Failure/timeout clears matching intent and resnapshots;
late effects are external reality. No mutation retry. Pending repeatedcreate and
regular-desktop navigation reject; same-Space focus/layout remain available. Same-
Space managed-previous is allowed only for active regular Core/nonfullscreen target.
Default configurable HyperD (user-selected after a host skhd conflict with C); digits focus only, N/P/0 unchanged. No delete/move command.

Environment: persistent owned debug guest macOS26.6.2/25G83, arm64, HS1.1.1, SIP/AX,
one guest display; reuse is not cold isolation. Host legacy restored/verified before
source edits/builds; no creation candidate host load. Every command≤120s. Fixed
functional gates5s completion/250ms matching/50ms sampling/150ms freshness/2pt geometry.
Real callbacks and independent native IDs/globalfocus/frames primary; caches secondary.

## Reviewed native evidence

Independent reviewer replayed frozen oracles/underlying observations and verified
924/924 hashes across13 runs (71/72 perrun). Core runtime28artifacts identical.

- regular creation41ca34de0bff:146assertions/14actions; oneadd/newD4/activation;
  rapiddoublecreate plusdigit/N/P/0 rejection; same-Spacej/k actualcallbacks before
  add; numbered/history return restores ABC columns/stack/order/selections/.55ratio.
- fullscreen782c9e7d1a42:71assertions/5actions; F1 source rebase, newD4 activation,
  retained unavailableD1slot and exitgeometry. Exitfocus restoration deferred.
- externalracee6417351ee91:101assertions; oneownedadd+oneexternalsetupadd→two actual
  identities, invalidation/cancellation/5stimeout, noownedselection/retry. Two distinct
  fixed5scheckpoints observe race then settlement; not5send-to-endstabletimeout gate.
  MC cleanup uncertain exposed, not speculative dismissal; explicit guest operator
  cleanup removes only owned emptytestSpaces. Fresh postcleanup nativebaseline3/MCabsent
  captured privately separately; processcleanup alone is not topology cleanup.
- switching42ade99366b9:249assertions/19actions/13confirmedlegs; Ghostty retention
  65ee2dcffbcb:142assertions/13actions. Normalcleanup/drain/noforcedteardown/no drops.
- Updated regular oracle862ac77284da and fullscreen switching270be081ffd2 PASS;
  supplemental review verified 144/144 frozen hashes and raw predicates/cleanup.
- Service expansion 4a4f4437478b then 2a7ac6ed1c72 PASS: two creations total;
  real phase-tagged j/k and two layout cycles during Add, plus j/k during selecting,
  actual D5 activation and native D1 return preserve exact layout/frames/focus.
  Last run's native cleanup records before/removed/after identities privately.
  Cross-Space versus same-Space managed-previous gate has composition coverage,
  not a separate native managed-previous acceptance claim.

Private raw/native data remain ignored under `.pi/poc/` and `vm/results/`.
Alias joins are source-reviewed; artifacts do not export raw native IDs. Frozen replay
uses guest acquisition/publication clocks; original host wall-clock delivery/ack times
are not persisted, limiting exact independent reconstruction of original deadlines.

## Measurements

Three11creation warm batches omit firstwarmup:30measuredwarm; fivefresh-runtimecold:
5measuredcold. All8 final batches PASS/71hasheseach/normalcleanup; each operation
returnsD1 and exact testcreated inactive desktop is removed as testsetup only.

| ms | Warm median / p95 / max | Cold median / p95 / max |
|---|---|---|
| posted→request |31.216 /34.388 /34.552|24.242 /24.980 /24.980|
| benignposted→callback |23.625 /26.163 /26.486|17.793 /18.981 /18.981|
| nativecompletion |720.839 /726.965 /728.273|702.644 /704.835 /704.835|

Independent C sender:100ordinaryYposts/100realhotkeycallbacks/exit0,64callbacks with
inFlight creation/switch. Median.635/p9513.898/max28.416ms, allnonnegative, flagsnone;
source restored/settled. Reviewer checked rawclocks/counts; ordinalpairing has no event
sequence token; phase coverage combines pending types. A second frozen sender run preserves executed binary bytes, candidate root in actual
trace and guest hash inventory; 100/100/exit0, 63 pending callbacks, median .650 /
p95 13.710 / max 27.654 ms. Exact probe-created ID removal and original ordered IDs,
source and MC absence verified privately after stop. Supplemental review verifies
preserved bytes/root and raw clocks; final delta review verifies 72/72 last service hashes, 188 raw assertion joins,
both service phases, named native cleanup and 30/30 guest inventory hashes.
Inventory is not atomic with process launch; that limitation remains explicit. Narrowguest
workload not physicalhost/representative slowapp certification. Instrumentation
before/after counters retained; not comprehensive AX/render/query-budget acceptance.

## Failures / fixes retained

- First probe shared-path missing beforeeffects; frozen SSH copy repaired. Retrieval
  base64 syntax and earlynofile repaired, not platformbehavior.
- Initial native burst whitelist omitted create; rejected beforemutation. Fixed harness.
- 8b912208f826/1fea4a17dda2 scenarioPassedtrue but overallFAIL cleanuptransport;
  original firstexceptionunknown, second JSONparseerror captured. Fresh underlying
  normalcleanup does not relabel failedrun. Stop now compactack separately from
  status confirmation, rawfuture IPCerrors preserved. Subsequentrunsnormalcleanup.
- Initial benchmark allnativewindowIDs emptiness wrongly counted overlays; testcleanup
  checks exact ownednewidentity/inactive/emptyfixturebaseline, not productiondeletion.
- f69f36f22596 switchingFAIL150ms freshness; kept despite passing42ade regression.
- Race57a6aa09c3a9 correct5stimeout could not also meet250msstablewindow starting at
  command under5sgate; split actualrace/settlement gates, thresholds unchanged.
- Independent highsource review found/fixed3Important defects: append/sourceconflict
  stranded tuple, inherited selectiondeadline, unchangedfullIDs/typechange authority.
  Secondreview confirms sourcefixes/noresidualHighMedium; regressions added.
- Found15existing adaptertests omitted from suite runner; now included pluscreation
  coverage. Historical265passing did not include adaptertestfile; no retroactive claim.

## Remaining qualification / cleanup

No atomic attribution/MC lifetime guarantee. Compatible append after ambiguous add
cannot exclude indistinguishable external singlecreate; conservatively handles observed
conflicts without duplicate mutations. No hostperformance/fullappmatrix claim.
Fault/shutdown/late receipt sequences are pure injected evidence, not nativefaults.
Guest source/probes stopped and topology restored afterownedcleanup; host solelegacy
unchanged. Source/oracle/evidence reviews completed with stated qualifications. Loader review
fixed rollback-target and cleanup-exception defects; 26-artifact creation manifest
matches, expected 25 enabled Hyper bindings checked. Read-only host preflight confirms
legacy sole registered runtime/26bindings and HyperC system-assignable. The first
authorized manual host trial exposed skhd consuming HyperC for Chrome mode; system
assignability did not establish external-hotkey conflict freedom. User selected
HyperD; actual skhd config contains no D binding. Binding-only source/default/example
and real callback tests updated; no skhd edits or automated host window/Space tests.
