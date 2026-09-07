# POC-001 direct-AX volume — analyzer and executable next slice

**Status: reviewed real-host adapter and CLI are implemented; no live action was
performed by this change.** `direct_ax_volume_analyzer.py` and
`direct_ax_volume_normalizer.py` remain private evidence readers; **not a live runner**. `direct_ax_volume_controller.py` wires the reviewed
`direct_ax_volume_real_host.py` ports for the explicitly approved controller
commands: `prepare`, `status`, `warm-start`, `warm-sample`, `warm-finish`,
`cold-sample`, `cold-finish`, and `abort-cleanup`. The controller has no autonomous batch loop: each sample is
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

`prepare` allocates the controller's initial storage directory exactly once:
`/tmp/p1d.XXXXXX` under `umask 077`. Each cold sample separately allocates one
fresh owner-private fixture session directory under the same short prefix so a
new fixture never reuses a trace or socket. Every allocated directory is
verified owner `0700`; state and evidence use no-follow atomic replacement at
owner `0600`. Each fixture socket remains at the short canonical
`/tmp/p1d.XXXXXX/poc001-fixture.sock` path. Every controller command installs
one shared monotonic deadline of at most 120 seconds: each build, IPC, marker,
status, normalizer, analyzer, shutdown, and process wait receives only its
remaining budget. Failure cleanup runs as one separately bounded recovery
command (also at most 120 seconds), never as extra sample time. Marker waiting reads complete NDJSON lines
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
# Cold starts only after warm-finish records `passed`. Invoke one command per
# separately approved index; do not loop or batch these five destructive runs.
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py cold-sample --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX --index 1
python3 pocs/001-window-events-liveness/direct_ax_volume_controller.py cold-finish --execute --approval-file /absolute/private/approval.json --run-dir /tmp/p1d.XXXXXX
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

## Executable cold slice — isolated first-create samples

`cold-sample N` is accepted only after `warm-finish` has persisted a passing,
fully cleaned warm class, and only for the exact next `N` in `1..5`. A warm
failure does **not** authorize cold collection. Each command captures and
durably writes a new exact legacy semantic baseline and cleanup intent before
any fixture, legacy, or observer mutation. It then builds/spawns a **fresh**
fixture process in a new owner-private session directory/socket, rejects stale
PID/socket state, stops legacy semantically, clears the approved observer module
cache, and starts one fresh observer.

It sets trace scope to exactly `cold-N`, arms `direct_ax` once with generation
`1`, performs exactly one create and one close, and uses the same bounded
fixture-marker/correlation sequencing as a warm sample. It records
pre-close facts and post-finish/reset facts from the observer, then exports and
stops the observer, verifies its stopped counters, shuts down/waits for the
identity-checked fixture, verifies exact process/socket absence, and restores
all legacy bindings/watchers/bar to the captured baseline. The final stopped
session record is evidence-derived; it is not inferred from an intended
cleanup. The normalizer receives all three snapshots and appends a row only
when the normalizer and sample analyzer validate it.

A timeout, malformed/unsafe evidence, cleanup uncertainty, interrupt, or
normalizer failure preserves the private evidence, performs idempotent cleanup
once, and becomes `indeterminate`; it never retries the sample. A schema-valid
sample analyzer rejection is a substantive `failed` result. Every process,
marker, status, and analyzer command is bounded at no more than 120 seconds.

`cold-finish` accepts exactly the ordered rows `cold-01` through `cold-05`,
each with generation `1` and its own successful cleanup. It writes the
observed class-final cleanup record, runs the cold class analyzer (including
p95), persists `cold_passed`, `failed`, or `indeterminate`, and retains the run
tree. It has no unattended five-sample loop.

## Evidence normalization and subsequent batches

The normalizer consumes only already-retained private fixture trace/response,
running observer export, pre-close/post-finish observer status snapshots, and
one retained session-status input. For cold that final input is the observed
stopped observer/fixture session; for warm it is the already-retained
post-finish running observation and is not a cleanup claim. It joins only on
the frozen full alias; it never joins on title, PID, native ID, focus,
visibility, Space, or timing. Sample/class analyzer commands remain:

```sh
python3 pocs/001-window-events-liveness/direct_ax_volume_normalizer.py warm "$CREATE_RESPONSE" "$FIXTURE_TRACE" "$OBSERVER_EXPORT" "$PRE_CLOSE_STATUS" "$POST_FINISH_STATUS" "$SESSION_STATUS" "$ROW_JSON"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py sample warm "$ROW_JSON" "$SAMPLE_RESULT"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py class warm "$WARM_CLASS_JSON" "$WARM_RESULT"
```

Before recording any failure, independently inspect retained private evidence
for harness, stale state, operator, normalizer, and analyzer defects. This
adapter does not authorize a new live batch or change POC-001's `hypothesis`
status.
