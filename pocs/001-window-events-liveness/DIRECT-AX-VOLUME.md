# POC-001 direct-AX volume — analyzer and executable next slice

**Status: reviewed real-host adapter and CLI are implemented; no live action was
performed by this change.** `direct_ax_volume_analyzer.py` and
`direct_ax_volume_normalizer.py` remain private evidence readers; **not a live runner**. `direct_ax_volume_controller.py` wires the reviewed
`direct_ax_volume_real_host.py` ports for the explicitly approved controller
commands: `prepare`, `status`, `warm-start`, `warm-sample`, `warm-finish`, and
`abort-cleanup`. The controller has no autonomous batch loop: each sample is
one separately invoked, explicitly approved command.

## Frozen safety boundary

Every mutating command requires both `--execute` and an already-existing,
absolute owner-private (`0600`) approval JSON file:

```json
{"approved_commit":"<exact full HEAD SHA>"}
```

The controller rejects a non-clean repository, including every staged,
unstaged, and untracked porcelain-v1 `-z` record (including rename/copy
counterparts), a non-exact current full `HEAD`, or a changed HEAD after
preparation. `status` requires neither flag nor approval; it is read-only and
returns only phase and redacted booleans—never paths, PIDs, sockets, tokens,
aliases, responses, or trace records.

`prepare` is the only storage allocator. It creates exactly
`/tmp/p1d.XXXXXX` under `umask 077`, verifies owner `0700`, and writes state
and evidence by no-follow atomic replacement at owner `0600`. The fixture
socket remains the short canonical
`/tmp/p1d.XXXXXX/poc001-fixture.sock` path. Every command/process wait has a
hard limit of at most 120 seconds. Marker waiting reads complete NDJSON lines
only, rejects malformed complete records, ignores only a final incomplete
line, and prints nothing.

## Exact future operator commands — **do not run without a separate human gate**

From the repository root, after the approving human has created the private
approval file and confirmed the exact frozen commit:

```sh
# No --execute: safe redacted inspection only.
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py status --run-dir /tmp/p1d.XXXXXX

# Each is mutating and requires a separately approved private exact-HEAD file.
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py prepare --execute --approval-file /absolute/private/approval.json
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py warm-start --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX
# Invoke exactly once per approved generation, 1 through 30; no retry.
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py warm-sample --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX --generation 1
# Only after 30 analyzer-validated rows.
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py warm-finish --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py abort-cleanup --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX
```

Before `prepare` creates a directory, the adapter captures and validates
redacted macOS build, architecture, Hammerspoon version, branch/full commit,
built-in display identity, and required-settings evidence. Missing evidence is
a refusal, not a best-effort record.

`warm-start` invokes only the canonical fixture build script
`fixture/scripts/build-fixture.sh`, spawns the canonical bundle binary with
`POC001_FIXTURE_CLOCK_KIND=mach_absolute`, persists the cleanup intent before
any legacy mutation, and waits for schema-valid `run_started` and
`socket_ready` records whose fixture `sample_id` is exactly `startup`. It
captures the exact legacy restoration baseline: started state, configured
hotkey count (the current configured **26**-style count), installed binding
count, lifecycle filter, reconcile timer, bar timer, and exact canvas count.
It operates only on the already-loaded `spoon['10bucks']` object—never a
second `dofile` object. It then stops and
verifies legacy, clears only `trace`, `lifecycle`, `ownership`,
`private_export`, `correlation`, and `observer`, and starts/verifies the
observer.

Cleanup is idempotent: abort correlation, stop/export observer and verify zero
open callbacks/timers/window effects/correlation map, request fixture shutdown,
terminate/wait only if still alive, and verify the PID and socket are absent.
Before any signal, the persisted PID identity is rechecked against the exact
canonical fixture executable and its `POC001_FIXTURE_RUN_DIR` environment, so
PID reuse cannot target an unrelated process.
It then performs one semantic legacy restore: `start()`, **explicit
`bindHotkeys()`**, and exact comparison of the complete captured baseline.
Any cleanup or restoration uncertainty persists `indeterminate`, returns
nonzero, retains the run directory and its evidence, and never deletes it.

## Executable next slice — warm samples and finalization

`warm-sample N` is accepted only for a running warm session and its exact next
generation (`1..30`). It sets the observer trace sample to exact `warm-N` before it arms `direct_ax`
once, creates one fixture window, waits (each wait is bounded at 120 seconds)
for fixture-visible plus correlation readiness/map `1`, snapshots status, closes
once with the private response token, waits for `native_close_completed` and
both alias-bearing candidates, and finishes correlation once. Correlation
waiting is an external controller bounded status wait: it creates no observer
timer or permanent POC poll, and a timeout is retained as private evidence. It writes a
post-finish snapshot and a running observer trace export, normalizes private
evidence, runs the sample analyzer, then appends only a validated row and
persists the next generation. The controller verifies the snapshot's exact
correlation facts and independently identity-checks fixture process plus socket
before adding `fixture_running`; the observer never fabricates fixture state. A timeout, normalizer failure, or analyzer error
uses semantic abort cleanup without retry and retains all private evidence.
`KeyboardInterrupt`/SIGINT follows that same cleanup/restoration path once,
then exits nonzero.
A schema-valid substantive analyzer failure remains `failed`, distinct from
`indeterminate` harness/evidence failure.

`warm-finish` requires exactly 30 validated rows. It stops and exports/quiesces
the observer, shuts down the fixture and verifies its recorded identity/socket
are absent, restores the exact legacy baseline (including bindings), derives
private `class_final_cleanup`, and runs the warm class analyzer. It preserves
the run tree and persists `passed`, `failed`, or `indeterminate`; it never
claims that an analyzer or cleanup error is platform evidence.

## Evidence normalization and subsequent batches

The normalizer consumes only already-retained private fixture trace/response,
running observer export, and before/after observer status snapshots. It joins
only on the frozen full alias; it never joins on title, PID, native ID, focus,
visibility, Space, or timing. Sample/class analyzer commands remain:

```sh
python3 pocs/001-window-events-liveness/direct_ax_volume_normalizer.py warm "$CREATE_RESPONSE" "$FIXTURE_TRACE" "$OBSERVER_EXPORT" "$PRE_CLOSE_STATUS" "$POST_FINISH_STATUS" "$ROW_JSON"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py sample warm "$ROW_JSON" "$SAMPLE_RESULT"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py class warm "$WARM_CLASS_JSON" "$WARM_RESULT"
```

Before recording any failure, independently inspect retained private evidence
for harness, stale state, operator, normalizer, and analyzer defects. This
adapter does not authorize a new live batch or change POC-001's `hypothesis`
status.
