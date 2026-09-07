# POC-001 direct-AX fixture correlation volume

**Status: retained runner/procedure only; no live action is authorized.** This
procedure is the next human-gated slice after the recorded direct-AX smoke. It
does not change POC-001's `hypothesis` status, select a destruction authority,
or authorize production work. The retained analyzer is
[`direct_ax_volume_runner.py`](direct_ax_volume_runner.py); its pure tests are
[`test_direct_ax_volume_runner.py`](test_direct_ax_volume_runner.py).

## Frozen protocol

Freeze the source commit and this document before requesting approval. The only
correlation source is **`direct_ax`**. There are exactly **30 warm** samples and
exactly **5 cold** samples; do not substitute filter samples, add retries, or
change a threshold after observing a result.

- **Warm:** one observer session and one fixture process; sequentially create,
  correlate, close, verify candidates, and finish 30 generations. Each
  generation is armed once with `arm_fixture_correlation(generation,
  "direct_ax")`.
- **Cold:** five separate first-create samples. Each has a fresh fixture
  process *and* a fresh observer start/cache. Do not arm a second generation.
- Every sample has exactly one fixture create and exactly one fixture close.
  It performs one direct `windowElement` construction, one direct
  `AXIdentifier` read, zero filter correlation constructions, and zero filter
  identifier reads. It must have one map entry before close, exact full
  fixture/observer SHA-256 alias equality, and exactly one alias-bearing
  `direct_ax` and `filter` destruction candidate.
- Every destruction candidate is at most 1,000 ms after the fixture native
  close. A successful finish resets the map and source state. Missing,
  duplicate, malformed, or late correlation is substantive failure.
- Warm direct-correlation p95 is at most 100 ms. Callback processing across
  the warm class has p95 at most 50 ms and maximum at most 100 ms. Every cold
  first-create direct correlation is at most 3,000 ms; the cold callback
  p95/maximum gates remain 50/100 ms.
- POC-issued steady global queries, POC effects, and permanent polls are zero.
  Candidate filter callbacks remain destruction diagnostics only; they do not
  consume correlation or select an authority.

Stop the affected class on the first substantive failure. Preserve the private
evidence, do not retry that sample, and do not start a later sample in that
class. A p95 failure becomes knowable only after the final required sample; it
ends that class immediately and still does not permit a threshold change.

## Private paths, output, and cleanup

Use `umask 077`. Create the per-run directory only with the short template
`/tmp/p1d.XXXXXX` (mode `0700`); the fixture socket is exactly
`/tmp/p1d.XXXXXX/poc001-fixture.sock`. Do not use a nested `$TMPDIR` path.
Every private trace, response, status record, input array, and aggregate is
mode `0600`, owner-only. The runner refuses non-`0600` input.

Raw fixture responses and observer exports remain private. The analyzer accepts
only a locally normalized, redacted record: aliases and timings may be input,
but its aggregate intentionally emits no alias, raw AX value, title, PID,
native ID, token, bundle ID, socket path, response, URL, or filesystem path.
Sensitive keys cause `analyzer_error`, not a platform result.

Install cleanup before legacy is stopped. On **every** normal, failed,
interrupted, or analyzer-error exit: stop/export the observer if loaded; abort
any armed correlation; shut down or terminate and wait for the fixture; verify
fixture process/socket absence; verify observer stopped with callbacks/timers/
effects/map all zero; then restart and verify legacy 10bucks. Preserve the
private directory and all evidence on failure. Never delete evidence in a trap.

## Human-gated execution procedure

Do not execute this section without explicit human approval for the estimated
**8–12 minute** disruption (30 warm plus 5 cold disposable window samples).
Split commands into observable batches with command timeouts no greater than
120 seconds. No command should combine the entire volume into one unattended
step.

1. **Preflight:** require clean frozen source, record the full commit and
   environment privately, confirm no observer/fixture is already present, and
   build statically only. Do not treat a static build as live evidence.
2. **Prepare the private run directory and cleanup trap** as above. The trap is
   installed before stopping legacy. Stop legacy only after all preflight gates
   pass; load the observer from the frozen absolute POC path, clearing only
   `trace`, `lifecycle`, `ownership`, `private_export`, and `correlation` from
   `package.loaded`.
3. **Warm batch:** launch one fixture with `POC001_FIXTURE_CLOCK_KIND=mach_absolute`.
   For generation 1 through 30, use source `direct_ax`, collect the private
   fixture response/trace and stopped observer export, then create exactly one
   normalized redacted sample record. Check it with the runner before issuing
   the next generation. Any substantive failure stops the warm batch.
4. **Cold batch:** for each of five samples, fully clean the preceding run,
   start a fresh observer and fresh fixture process/cache, and issue exactly
   one first create/close. Analyze its one normalized record before the next
   cold process is started. A fixture exiting before create is a
   harness/preflight issue: retain evidence and independently inspect it; do
   not call it a platform failure.
5. **Class analysis:** after exactly 30 valid warm or 5 valid cold records,
   serialize the corresponding normalized array to a private `0600` JSON file
   and run:

   ```sh
   python3 pocs/001-window-events-liveness/direct_ax_volume_runner.py warm /private/warm.json /private/warm-aggregate.json
   python3 pocs/001-window-events-liveness/direct_ax_volume_runner.py cold /private/cold.json /private/cold-aggregate.json
   ```

   The paths above are illustrative only and must resolve inside the short
   owner-private run directory. The process exits `0` for pass, `1` for a
   schema-valid substantive failure, and `2` for `analyzer_error`/
   `indeterminate`. Exit 2 is never platform evidence. Review the underlying
   private trace/export, stale module/process state, operator timing, and
   normalizer/analyzer correctness before recording any platform conclusion.
6. **Only after cleanup and independent review**, commit a redacted aggregate
   to the canonical POC result. Do not commit raw inputs, results containing
   aliases, private paths, or a claim that analyzer refusal is a platform
   failure.

## Normalized sample schema (private input only)

Each row is a JSON object containing only `sample_id` (`warm-01` …
`warm-30` or `cold-01` … `cold-05`), `source`, `fixture_alias`,
`observer_alias`, `map_count_before_close`, `direct_constructions`,
`direct_identifier_reads`, `filter_constructions`, `filter_identifier_reads`,
`direct_candidates`, `filter_candidates`, `direct_correlation_ms`,
`callback_durations_ms`, `steady_global_queries`, `window_effects`,
`permanent_polls`, and `cleanup`. Candidate objects contain only `alias` and
`latency_ms`. Cleanup contains only the boolean/count gates checked by the
runner. The normalizer must derive these fields from the retained raw private
fixture trace/response and stopped observer export; it must not use title,
timing proximity, PID, native ID, focus, visibility, Space, or any fallback
identity input.

The runner is intentionally pure analysis: it does not launch the fixture,
load Hammerspoon, stop/start legacy, or remove files. That makes its tests safe
and prevents a malformed analyzer input from mutating the live environment.
