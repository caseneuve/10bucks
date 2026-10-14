# Chooser relevance ranking — scoped correction

## Status and decision

**Verified:** ranked title/application-name search replaces boolean subsequence
filtering. **User-rejected scope interpretation:** this checkpoint incorrectly
interpreted MVP as already-discovered windows only. All ordinary managed windows
across regular desktops remain required; their cold-start discovery was not delivered
here. Only fullscreen/minimized cold-start discovery is deferred to
[`TODO0003`](../../todos/0003-chooser-global-unavailable-window-discovery.md).
Existing already-discovered unavailable rows remain retained; restoration selection
is still deferred. No global discovery helper, compiled scorer or truncation added.

CHOOSE-003 distinguishes stable cached admission order from query relevance order.
CHOOSE-004 defines exact-field, boundary-contiguous, contiguous, boundary-start
subsequence, then other subsequence quality. Within a class, fewer character gaps
and earlier start wins. Fields score independently; application-name matches win
only at equal quality, never ahead of a stronger title match. Admission order breaks
remaining ties. Empty queries restore admission order. Matching uses literal ordered
UTF-8 characters with ASCII case/boundary semantics, not Unicode normalization.

One pure scorer/projection changes; existing row reducer, membership/resource
owners, UI adapter and focus effects remain unchanged. Monotone earliest-successor
cursors find the best alignment across all starts, counting character distances
without repeating whole-prefix scans. Safe early exits follow absolute class/gap
bounds. No persistent normalized cache or alternative matcher.

## Pure checks and representative performance

319 Lua checks include generic relevance classes, short Inbox-like queries,
application/strong-title priority, ties, repeated characters, later compact alignment,
Unicode character gaps, literal symbols, immutable rows/leases and exhaustive small
alignment comparisons. 61 Python oracle checks cover native scenario failures.

User requested 100-character performance after clarifying ordinary title lengths.
Full filter/sort of 1,000 repetitive 100-character titles measured CPU time:
`in`3.85ms, `inb`15.37ms, `nbn`14.74ms; late no-match queries2.61–3.15ms.
These are representative pure measurements, not native key/pixel latency.
Actual titles are not truncated. The earlier 1,005-character repetitive workload
takes roughly100ms in the retained Lua scorer as well as unsuccessful optimization
candidates; recorded failures
are retained, not waived or relabeled. User explicitly accepted the 100-character
workload for this MVP. No compiled algorithm was needed or adopted.

## Native functional acceptance

Owned persistent SIP-enabled guest, macOS26.6.2/25G83, Apple Silicon, HS1.1.1,
Accessibility enabled, one logical1024x768 display, menu auto-hide/MRU settings as
POC021. Coordinator sole native operator; host untouched during acceptance. Frozen
candidate/native binary/fixture/observers/scenario, no editing executed artifacts.

`session-c4d353348b65`:89/89 frozen hashes,533 samples,439 assertion joins,
66 checkpoint occurrences,50 actions. Independent replay verifies every frozen
predicate and matching suffix. Minimum stable suffix250.030ms; maximum matching
acquisition gap103.795ms. No raw errors/drops, normal cleanup and worker drain.

Earlier admitted A has generic title `i---n---b`; later C has `Inbox`. Actual typed
`inb` must display C,A. Native Cmd2 selects exact A and confirms actual focus and
pending clearance, distinguishing visible rank from old admission position. Empty
query restores A,C. Initial fuzzy title/app tests, live title refresh, exclusions,
layout/focus order, cross-Space focus, unavailable rejection, closure and open-UI
cleanup remain covered by the existing full scenario. Expected order is independent
of the product scorer. Generic negative oracles reject reversed ranking, wrong
returned target and failure to restore empty-query order.

Existing POC021 setup-interval and inactive-unhide geometry qualifications remain;
this is settled-state acceptance, not continuous native-animation service proof.
The preparation reload IPC diagnostic is recorded separately from successful final
cleanup. No physical-host or broad application-matrix certificate.

## Separate benchmark population

Warm `f2d910d78b6e`, `0245c3c510d4`, `228760cef037`; cold `14a8f1d111dd`,
`7f18b1bfc8b9`, `169c00e525e9`, `b812a93a03d1`, `6ee6a626b351`.
57 identical frozen artifacts each /456 hashes;30 measured warm +3 labeled warmups,
5 fresh-candidate cold samples. Every run passed normal native UI/default bookkeeping,
wrapper/binding/resource cleanup, fixture quit and native-worker drain.

| ms: median / p95 / maximum | Warm30 | Cold5 |
|---|---|---|
| posted invocation → native isVisible |44.745 /64.150 /71.963|41.597 /53.742 /53.742|
| ordinary key after visible |11.296 /38.267 /39.613|17.848 /22.643 /22.643|

Opening global enumeration/icon counter deltas zero. Endpoint includes5ms observer
delay and native visibility property, not pixels. Cold means fresh candidate/chooser,
not OS-cache eviction. This observer measures opening/service, not 1,000 live-window
query stress; representative query CPU costs are above.

## Separate independent-sender stress

`chooser-ranking-stress-20261014`:53 frozen artifacts including guest-built executed
C sender and fixed analyzer.100 posts/100 actual callbacks, sender exit0;
28 chooser iterations including query/cancel,26 callbacks while chooser visible.
Nearest-rank service median3.924/p9527.310/max66.246ms. Explicit final native A,
desired/history A and local/global pending clear; normal fixture quit, candidate/UI/
binding cleanup and worker drain, no forced sender termination. Source-enforced
exact joins export aliased outcomes; ordinal post/callback pairing lacks an event
token. Query/cancel workload is not a replacement for functional ranking assertions.

## Review, cleanup and host configuration

Independent source and raw review checks simplicity, scope, relevance correctness,
resource authority, native predicates, benchmark populations and stress. Automated
lint detection found no recognized project type; explicit Lua/Python checks and
Swift fixture build/typecheck were used instead, not a fabricated lint certificate.

Guest cleanup separately verified zero ordinary test windows, original three regular
desktops/D1 and no running acceptance owner/sender. Earlier global-discovery probes
are recorded in TODO0003, not shipped as best-effort production discovery.

Repo default remains HyperW. The user's host configuration override is separately
requested as `hotkeys.chooseWindow = {{"cmd","alt","ctrl","shift"}, ";"}`;
user Thunderbird rules remain outside source/tests. Host readiness is recorded in
WORK_STATE only after explicit authorized frozen candidate/configuration load and
verification. No deferred close/movement bugs were changed.
