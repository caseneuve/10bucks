# POC-001 direct-AX volume — analyzer and executable next slice

**Status: source/test checkpoint; not a live runner and no live action was
performed.** `direct_ax_volume_analyzer.py` is a retained pure normal-record
validator, not an orchestrator. `direct_ax_volume_normalizer.py` is the
reviewed pure/private evidence adapter, not live orchestration: it reads one
already-retained create response, cumulative fixture NDJSON trace, stopped
observer export, a pre-close observer status snapshot, and a post-finish
observer status snapshot, then writes one private analyzer row. It joins fixture and observer only by the frozen full
alias; fixture trace intervals isolate a generation without exporting or
joining on the private close capability. This document provides the later live
batches rather than claiming that orchestration exists.

## Frozen semantics

The only source is `direct_ax`; exactly 30 warm and 5 cold samples are fixed.
Warm uses one observer and one fixture process across generations 1..30. Each
warm generation must finish/reset its correlation map/source but must **not**
stop the observer or fixture. Cold uses one fresh observer/cache and fixture
per sample; each fresh fixture trace and observer arm is generation 1, while
class order is fixed by sample IDs `cold-01` through `cold-05`. Every generation requires:

- exactly one create/close with the frozen request/trace sample ID
  `warm-01`…`warm-30` or `cold-01`…`cold-05`; the accepted create response,
  `create_requested`, and `native_close_completed` must name that same sample;
  map count 1 before close; one direct construction
  and `AXIdentifier` read; zero filter constructions/reads;
- exact full alias equality; exactly one alias-bearing direct/filter destruction
  candidate, each <=1,000 ms after native close;
- successful `finish_fixture_correlation`: map 0, armed false, candidate source
  null; zero effects, permanent polls, and steady global queries.

The required pre-close status snapshot must report correlation `map_count=1`,
`armed=true`, `candidate_source=direct_ax`, and no destruction candidate source
consumed. The distinct post-finish snapshot must report map zero, unarmed,
null candidate source, and both candidate-source flags reset. These snapshots
are evidence fields, not values inferred from correlation events.

Warm direct-correlation p95 <=100 ms. Callback p95 <=50 ms and max <=100 ms.
Every cold direct correlation is <=3,000 ms. Stop a class on its first
schema-valid substantive failure. Missing, ill-typed, unsafe, or contradictory
normalizer data is `analyzer_error`/`indeterminate`, never platform evidence.

## Approval and source boundary

Human approval for the estimated **8–12 minute** volume disruption was granted
**after preflight**, subject to orchestrator review of this checkpoint. It does
not authorize a live action yet. The frozen source/procedure boundary is
`223ba1c8f5357e903dcd91aeb06034b5e6aa8498` (`poc: clarify direct AX volume
analyzer boundary`). The operator must require a clean tree and byte-match the
frozen POC files before any live batch. This approval record is documentation
only and does not alter that frozen source. Commands must have timeout <=120
seconds.

## Private paths and final cleanup

Use `umask 077`, a `0700` directory exactly matching `/tmp/p1d.XXXXXX`, and
`/tmp/p1d.XXXXXX/poc001-fixture.sock`; never nested `$TMPDIR`. Private input,
trace, export, response, and output files are owner `0600`. The analyzer uses
atomic no-follow output creation and emits redacted aggregates only.

At class end (and every abort), stop/export observer, abort any arm, terminate
fixture, verify process/socket absent and observer callbacks/timers/effects/map
all zero, then perform semantic legacy restoration: start, rebind configured
hotkeys, and verify the exact captured nonzero binding count plus lifecycle
watcher/reconciler/bar state. `legacy_restarted`/`started=true` alone is not a
cleanup pass. The class-final record carries expected and actual binding counts
and expected/actual lifecycle, reconcile, and bar booleans. This
**class-final cleanup** is separate from each warm generation's finish/reset
gate. Preserve all private evidence.

## Executable controller state machine (source/test only; no sample command)

`direct_ax_volume_controller.py` now owns the POC-only lifecycle boundary.
It deliberately exposes **only** these commands: `prepare`, `status`,
`warm-start`, and `abort-cleanup`. It has no create/close/sample command and
ships no live macOS port adapter. Its source-only CLI refuses execution rather
than quietly selecting shell/Hammerspoon behavior.

A reviewed future adapter must inject its command/process/clock/filesystem
ports into `DirectAXVolumeController`; every subprocess request has an explicit
limit at or below 120 seconds. Every mutating command (`prepare`, `warm-start`,
and `abort-cleanup`) requires `--execute`, a pre-existing owner-private `0600`
approval JSON file containing the exact `approved_commit`, a clean full frozen
HEAD commit, and a repo-relative staged/unstaged/untracked preflight. `status`
is read-only and emits only redacted booleans/phase, never a PID, socket path,
token, alias, response, or trace content.

`prepare` is the only command that allocates storage. It uses `umask 077` in
its future filesystem port to create exactly `/tmp/p1d.XXXXXX` at `0700`, then
opens the controller state and evidence files at `0600` before writing the
private environment/freeze record. Its only permitted normal output is that
private run directory.

`warm-start` statically builds the canonical fixture, captures the complete
legacy semantic baseline (started state, configured binding count, lifecycle
watcher, reconciler, and bar state), and writes durable `cleanup_pending` state
with that baseline **before** stopping legacy. It launches exactly one fixture
in `mach_absolute` mode, waits (bounded) for `run_started` and `socket_ready`,
verifies its process/socket, then stops/verifies legacy, clears only the
approved POC modules, starts/verifies the observer, and writes `running`. Any
partial startup takes the same abort-cleanup path.

`abort-cleanup` is idempotent. It aborts correlation; stops/exports the
observer; requests fixture shutdown, terminates/waits if needed; verifies the
fixture process/socket are absent and observer callbacks/timers/effects/map are
zero; and invokes one semantic legacy restoration action: **start, rebind the
configured hotkeys, then verify** the started state, exact captured (nonzero)
binding count, lifecycle watcher, reconciler, and bar state. `started=true`
with zero bindings is restoration failure, not cleanup. It never deletes
private evidence. A failed restoration is persisted as `indeterminate` and
returns nonzero rather than claiming cleanup succeeded. Persisted
`running`/stale PID/socket state cannot be reused by `warm-start`.

## Executable next slice (not run)

The reviewed live orchestrator/normalizer must implement these literal batches;
no batch exceeds 120 seconds and the next batch starts only after the previous
private analyzer output is reviewed:

```sh
# Per generation, the pure normalizer consumes only already-retained private files.
# It performs no launch, socket, Hammerspoon, or process action and writes ROW_JSON mode 0600.
# PRE_CLOSE_STATUS is captured before close; POST_FINISH_STATUS is captured after finish.
python3 pocs/001-window-events-liveness/direct_ax_volume_normalizer.py warm "$CREATE_RESPONSE" "$FIXTURE_TRACE" "$OBSERVER_EXPORT" "$PRE_CLOSE_STATUS" "$POST_FINISH_STATUS" "$ROW_JSON"
# After it has written the analyzer schema row:
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py sample warm "$ROW_JSON" "$SAMPLE_RESULT"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py sample cold "$SAMPLE_JSON" "$SAMPLE_RESULT"
# After the class-final cleanup record exists, with CLASS_JSON={samples,class_final_cleanup}:
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py class warm "$WARM_CLASS_JSON" "$WARM_RESULT"
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py class cold "$COLD_CLASS_JSON" "$COLD_RESULT"
```

The normalizer must derive fields only from retained private fixture trace /
response and stopped observer export; it must never join using title, PID,
native ID, focus, visibility, Space, or timing. Per-row required fields are
`sample_id`, `generation`, source/aliases, create/close/query counts, candidates,
direct correlation/callback timings, `generation_reset`, and
`session_after_generation`. `class_final_cleanup` is required only for class
mode. Sample mode enables the mandated check before the next generation.

Exit 0 is a passing check, 1 a schema-valid substantive failure, and 2 an
indeterminate analyzer boundary. Before recording any failure, independently
review raw private evidence for harness, stale module/process, operator, and
normalizer/analyzer defects. No result is committed except a redacted aggregate.
