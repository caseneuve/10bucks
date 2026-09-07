# POC-001 direct-AX volume — analyzer and executable next slice

**Status: source/test checkpoint; not a live runner and no live action was
performed.** `direct_ax_volume_analyzer.py` is a retained pure normal-record
validator, not an orchestrator. The executable live orchestration/normalizer is
the next reviewed slice; this document provides its exact short batches rather
than claiming it exists.

## Frozen semantics

The only source is `direct_ax`; exactly 30 warm and 5 cold samples are fixed.
Warm uses one observer and one fixture process across generations 1..30. Each
warm generation must finish/reset its correlation map/source but must **not**
stop the observer or fixture. Cold uses one fresh observer/cache and fixture
per sample, with global sample generations 1..5. Every generation requires:

- exactly one create/close; map count 1 before close; one direct construction
  and `AXIdentifier` read; zero filter constructions/reads;
- exact full alias equality; exactly one alias-bearing direct/filter destruction
  candidate, each <=1,000 ms after native close;
- successful `finish_fixture_correlation`: map 0, armed false, candidate source
  null; zero effects, permanent polls, and steady global queries.

Warm direct-correlation p95 <=100 ms. Callback p95 <=50 ms and max <=100 ms.
Every cold direct correlation is <=3,000 ms. Stop a class on its first
schema-valid substantive failure. Missing, ill-typed, unsafe, or contradictory
normalizer data is `analyzer_error`/`indeterminate`, never platform evidence.

## Approval and source boundary

Human approval for the estimated **8–12 minute** volume disruption was granted
**after preflight**, subject to orchestrator review of this checkpoint. It does
not authorize a live action yet. The exact freeze commit is recorded in the
separate approval checkpoint following this source/test commit; the operator
must require a clean tree and byte-match the frozen POC files before any live
batch. Commands must have timeout <=120 seconds.

## Private paths and final cleanup

Use `umask 077`, a `0700` directory exactly matching `/tmp/p1d.XXXXXX`, and
`/tmp/p1d.XXXXXX/poc001-fixture.sock`; never nested `$TMPDIR`. Private input,
trace, export, response, and output files are owner `0600`. The analyzer uses
atomic no-follow output creation and emits redacted aggregates only.

At class end (and every abort), stop/export observer, abort any arm, terminate
fixture, verify process/socket absent and observer callbacks/timers/effects/map
all zero, then restart/verify legacy. This **class-final cleanup** is separate
from each warm generation's finish/reset gate. Preserve all private evidence.

## Executable next slice (not run)

The reviewed live orchestrator/normalizer must implement these literal batches;
no batch exceeds 120 seconds and the next batch starts only after the previous
private analyzer output is reviewed:

```sh
# Per generation, after a private normalizer has written SAMPLE_JSON mode 0600:
python3 pocs/001-window-events-liveness/direct_ax_volume_analyzer.py sample warm "$SAMPLE_JSON" "$SAMPLE_RESULT"
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
