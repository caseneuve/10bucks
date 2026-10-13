# Cached managed-window chooser — scoped delivery

## Status and scope

**Verified:** product checkpoint `4992324`, one cached managed-only chooser,
configured `chooseWindow` / HyperW,
through the existing native `hs.chooser` UI. CHOOSE-001/002/003/004, DISC-003,
FOCUS-003/006 and relevant state/query contracts have generic pure coverage and
settled-state native guest acceptance. Rules remain delivered; bugs0001/0002 are
untouched and deferred until after chooser.

Minimized, app-hidden and native-fullscreen managed windows remain listed.
Selecting a target requiring restoration rejects explicitly; restoration and
fullscreen destination effects remain roadmap step 5. Available regular targets
can be selected across discovered retained scopes. This is not a full release,
physical-host performance, representative-app matrix or host-manual-ready claim.

## Lean implementation

Existing retained Cores and FocusHistory unplaced records remain membership
owners; HandleRegistry remains native-resource authority. One pure ordered
primitive presentation array caches accepted admission/title/application data.
New rows append; duplicate readiness/title updates stay in place; accepted death
removes. Focus, availability, layout, relocation and Space changes do not reorder
survivors. Uncertain ownership retains rows without authorizing selection.

The pure stable subsequence filter searches title or application without native
queries or relevance sorting. A thin native adapter owns one chooser, refreshes
visible choices, and hides before deleting on stop. No icons, second registry,
rank allocator, normalized-text cache, queue, epoch, callback wrapper or product
diagnostic machinery. Selection validates the returned exact lease against the
current registry and managed availability, then uses the narrowly extracted
existing committed global-focus request / Core selection / Host effect / actual
focus confirmation path. Previous-window behavior is unchanged.

Installed HS1.1.1 chooser Lua/docs and upstream matching implementation were
inspected first. Native matching is substring, not fuzzy; queryChangedCallback
delegates filtering to Lua. Owned-guest API probe verified Cmd1..9 and filtered
visible-row selection. Native hide/default focus restoration precedes completion;
the global callback remains unchanged. Default restoration is not separately
timestamped as an effect in composed evidence.

## Environment and fixed acceptance

Owned persistent SIP-enabled Tart guest, macOS26.6.2/25G83, Apple Silicon,
HS1.1.1, one1024x768 logical display, Accessibility enabled, unlocked console,
menu auto-hide on, MRU rearrangement off, Hammerspoon Dock icon hidden (native
chooser prerequisite above fullscreen). Original three regular desktops/D1.
Host stayed on its separate frozen rules candidate; no host reload/actions.

Functional, benchmark and stress responsibilities are separate. Coordinator is
sole native operator. Every executed candidate, native binary, fixture and helper
is frozen and hashed. No corrective focus, threshold relaxation or unchanged
failure rerun. Private native data remain ignored under `vm/results/` and `.pi/`.

Functional gates:5s eventual,250ms matching stability,150ms freshness,2pt geometry.
The fixture publishes opt-in AppKit geometry/key/active/lifecycle/title and explicit
windowWillClose facts. Current frontmost PID plus fixture key/active facts prove
focus; held native resources and accepted leases prove identity. Missing snapshots
or rows are uncertainty, not death. Snapshot sequence/time/age are checked through
publication. Other scenarios retain their existing observer.

Six explicitly recorded lifecycle **setup** intervals settle before acceptance:
fresh requested flag, with fullscreen additionally matching exact native owner,
active Space and expected type stable250ms, within3s. Sampling is never suspended
around chooser selection/rejection or measured product commands. Setup animation
time is not continuous service acceptance. Final-only geometry checks active A/C
and excluded B while retaining exact live A/B/C/D and inactive D2 ownership;
initial/all-frame geometry gates remain strict. Rejection checks retain native
focus, lifecycle, exact identity and completion assertions.

## Functional result

`session-57157a84c0a1`: independent review verifies89/89 hashes,486 raw samples,
393 assertion joins,43 actions,59 checkpoint occurrences /56 unique labels.
Every frozen predicate independently replayed. Minimum matching suffix250.009ms;
maximum matching acquisition gap104.581ms; maximum publication13.077ms;
maximum fixture-snapshot age82.938ms. No errors/drops; normal unforced quit,
resource/wrapper cleanup and native-worker drain.

Native checks cover managed/excluded scope, global stable rows, title/application
fuzzy search, actual filtered Cmd2 target, live title refresh, focus/layout order,
cancellation, unchanged-target pending clearance, regular cross-Space focus,
minimized/hidden/fullscreen listing and rejection, restore order, explicit native
close removal, and stop while chooser is open. Native chooser disappearance and
default focus bookkeeping release were verified.12 chooser,2 layout and1 numbered
shortcut callbacks were received; accepted targets C/A and three explicit
restoration-deferred rejections were joined to exact owned resources.

## Measurements

Separate benchmark runs, identical57-artifact manifests each (456 verified):
warm `453fe7e0f985`, `a7ad98a5d670`, `1662866b839b`; cold `df11df6c9df2`,
`b2e511ddcf96`, `7125411f0c3f`, `67cccba8bbd0`, `dd9cb68aa986`.
30 measured warm +3 labeled warmups;5 fresh-runtime/first-chooser cold samples.

| ms: median / p95 / maximum | Warm30 | Cold5 |
|---|---|---|
| posted invocation → native isVisible |43.404 /64.955 /83.549|42.657 /46.566 /46.566|
| ordinary key service after visible |9.161 /36.776 /40.070|15.818 /18.479 /18.479|

Invocation receipt→command-return p95/max warm13.536/14.212ms,
cold17.634/17.634ms. Opening enumeration/icon deltas zero; resource counts recorded;
all native UI/default bookkeeping, wrappers, bindings, fixture quit and worker
cleanup verified. Endpoint includes5ms observation delay and native visibility
property, **not pixel presentation**. Cold is fresh candidate/chooser, not reboot
or OS-cache eviction. Guest statistics do not certify physical-host latency.

Separate independent-sender stress `chooser-stress-20261013-r1`:53 frozen artifacts
including guest-built executed C sender.100 posts/100 actual callbacks, sender
exit0;28 chooser iterations with query/cancel and repeated selection;27 callbacks
while chooser visible. Service median8.554/p9530.167/max83.758ms. Explicit final
native A, desired/history A and no pending requests; normal fixture quit,
chooser/binding cleanup, worker drain, no forced sender termination. Ordinal
post/callback pairing lacks an event token; this is a narrow guest workload.
The original analyzer failed on empty Lua flags encoded as[]; preserved executed
artifacts were not edited. A separately hashed deterministic reanalysis accepts
only an empty array or all-false flag map. No native rerun was used for this repair.

## Retained failures and qualifications

- `d3b1de3f2020`: focused minimize setup, publication567.235ms / alias-C native
  acquisition559.910ms; FAIL unchanged.
- `74eafb05bcac`: changed background minimize, later restore publication534.723ms /
  alias-C530.833ms; earlier alias-B570.138ms also retained. FAIL unchanged.
- `680ac106cde9`: chooser activation focus read239.978ms / publication247.655ms;
  acquisition gap300.654ms. FAIL unchanged.
- `b9c2a3df70dd`: setup attempted from retained D2 instead of D1, before candidate/
  fixture start; incomplete cleanup certificate remains false. Explicit owned
  guest D1 preparation fixed procedure, not product behavior.
- `64e93863efd9`: AppKit observer still polled AX validity/native ID; alias-C
  loop543.677ms and stale snapshot publication. Individual-call attribution
  remains unproved. Recurring unnecessary chooser AX reads were removed.
- `3c2bbcf44f18`: harness assumed Session.windows owned joins; actual guest joins
  owned the existing byId map. Direct pure lookup repaired the assumption.
- `7d5be2efd7e3`: fixture snapshot aged during its own minimize animation;
  publication spans were short. Explicit setup settling replaced animation-wide
  acceptance, without weakening subsequent freshness/stability gates.
- `91bb47c34bcb`: fullscreen flag settled56.569ms before native activation;
  inter-sample gap578.819ms, recorded query spans≤6.029ms. Blocking call remains
  unattributed. Exact native-owner setup stability now precedes chooser checks.
- `eac9c33c5c8d`: inactive D2 member had640x512 rather than previous tiled geometry
  after app hide/unhide. Cause and responsible effect are unresolved. This remains
  a restoration/layout qualification, not an invariant waiver or chooser zero-frame
  effect claim. Final geometry scope was explicitly reviewed, not globally relaxed.

Accepted functional setup intervals contain649.192/615.366/1137.810/907.929ms raw
gaps. No uninterrupted native-animation/AX-query service claim. Later green runs
never repair earlier failures. No deferred close/movement bug was fixed.

## Review and cleanup

Independent review challenged ownership, total patch growth, source correctness
and raw evidence. Product adds140/removes1 lines; verification growth is much
larger and explicitly acknowledged, with one fixture observation owner and separate
functional/benchmark/stress procedures—not a product framework.

Final guest cleanup verifies0 ordinary test windows, original3 regular desktops/D1,
no running candidate/sender and drained worker. Frozen host remains unchanged.
Manual-host testing requires separate authority and actual candidate/configuration
loading verification; this evidence alone does not establish readiness.
