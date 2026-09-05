# POC-001 fixture--observer correlation — one human-gated smoke

**Status: completed once; no further run is authorized.** This was the
one-sample `window_filter`-selected live correlation smoke following the
implemented source and absolute-clock prerequisite in
[CORRELATION-HANDOFF.md](CORRELATION-HANDOFF.md).
Its result is recorded in the canonical POC document. It is not authorization
for a retry, volume run, POC-001 pass, destruction authority selection, or a
pending/next-key service claim. The earlier [fixture-only
calibration](fixture/LIVE-CALIBRATION.md) remains completed once and is not
repeated here.

## Separately gated direct-AX smoke (Target; not authorized)

A future direct-AX smoke is a separate one-sample procedure, not a retry or
continuation of this completed filter-selected run. It requires new explicit
human approval, a newly recorded frozen source checkpoint, and the same private
evidence/cleanup gates below. Its only procedural change is:

```lua
assert(POC001_OBSERVER:arm_fixture_correlation(1, "direct_ax"))
```

Only the exact fixture application's already-delivered `AXWindowCreated`
callback may consume that arm. It reads `AXIdentifier` once directly from that
callback's AX window element. The bundle check scopes the application but is not
identity evidence. The filter remains available for its existing lifecycle and
destruction-candidate instrumentation, but it performs zero correlation AX
element constructions/identifier reads and cannot consume the generation. Pass
requires the same alias-only join, raw cleanup, and direct/filter destruction
candidate alias retention; it does not select authority or authorize any live
action.

## Scope, hypothesis, and frozen boundary

**Hypothesis:** for exactly one controlled fixture create, the public AppKit
accessibility identifier can be read once from the delivered callback window;
the fixture and observer independently compute the same full alias; and both
observer destruction candidate paths retain that alias through controlled close.

This is one warm smoke sample, not a representative-app test. The human only
observes one disposable fixture window appear and disappear; they do not click,
focus, move, minimize, hide, switch Spaces, or otherwise interact with it or
another window. There is no `sleep`, retry, polling loop, global enumeration,
snapshot, title/native-ID/PID correlation, or pending-key action. In particular,
this smoke deliberately leaves the next-key service question **unresolved**.

The source boundary is frozen at commit
`4a125739406e8874a15d962021a36f483a91ea80` (the absolute-clock prerequisite commit). Before the
human authorizes the run, record its full object ID in the private environment
file and require a clean tree. The following code paths must byte-match that
commit; a difference is an abort, not an invitation to update the procedure:

```text
pocs/001-window-events-liveness/{observer.lua,correlation.lua,trace.lua,private_export.lua}
pocs/001-window-events-liveness/fixture/{Sources,Resources,scripts,Tests}
```

This document may be committed after the frozen source checkpoint; it is not a
fixture/observer code input. The static build below is made only from that
frozen fixture subtree. Generated `fixture/build` is ignored and must not be
committed.

**Pass for this smoke only:** exactly one identifier construction and one
`AXIdentifier` read; one valid full alias in the create response and observer
export with exact equality; `map_count=1` before close; both controlled
candidate paths carry that alias; maximum callback duration <= 100 ms; each
controlled destruction candidate <= 1,000 ms after fixture native close;
private cleanup succeeds. One sample cannot select an authority or establish a
p95. Any missing, duplicate, malformed, unequal, raw-data leak, timeout,
negative latency, observed sleep, prohibited query/input, or cleanup failure
is failure/unresolved; do not retry ad hoc.

## Approval gate and private evidence

A human must approve this exact document, one static build, one fixture launch,
one fixture IPC create/close/shutdown sequence, and one direct observer load.
The operator records approval, date, macOS/Hammerspoon versions, branch, full
`HEAD`, frozen commit, and redacted outcome privately. Do not paste or commit
raw trace/response files, raw token, native ID, title, PID, bundle ID, socket
path, or screenshot.

All run directories are newly created with `umask 077`, owner/mode `0700`; all
fixture responses, fixture trace, observer export, and local analysis output
are owner/mode `0600`. Retain those files on every abort. Only a redacted
aggregate may later be committed.

The commands below intentionally use a private observer-export path and emit
only fixed markers, counts, booleans, aliases, and aggregate latencies. They
never print the create response, fixture token, raw trace, raw AX value, native
ID, title, or PID.

## Exact one-sample procedure

Run from the repository root only after approval. The shell is deliberately
strict and installs its traps before any runtime is stopped. It does not issue
`hs.reload`, `open`, `osascript`, or a fixture build/launch as part of this
published document; the commands are instructions for the approved human only.

### 1. Freeze, create private storage, and static-build once

```sh
set -eu
umask 077
ROOT="$PWD"
FREEZE_COMMIT=4a125739406e8874a15d962021a36f483a91ea80
FIXTURE_SUBTREE='pocs/001-window-events-liveness/fixture'
FIXTURE="$ROOT/$FIXTURE_SUBTREE/build/POC001Fixture.app/Contents/MacOS/POC001Fixture"
FIXTURECTL="$ROOT/$FIXTURE_SUBTREE/build/POC001Fixture.app/Contents/MacOS/poc001-fixturectl"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/poc001-correlation.XXXXXX")"
OBSERVER_EXPORT="$RUN_DIR/observer-export.json"
ANALYSIS="$RUN_DIR/analysis.json"
FIXTURE_PID=''
OBSERVER_LOADED=0
LEGACY_STOPPED=0
FIXTURE_STARTED=0
NORMAL_COMPLETE=0

require_mode() {
  test "$(stat -f %u "$1")" = "$(id -u)"
  test "$(stat -f %Lp "$1")" = "$2"
}
require_mode "$RUN_DIR" 700
test "$(git rev-parse --is-inside-work-tree)" = true
test -z "$(git status --porcelain)"
git rev-parse --verify "$FREEZE_COMMIT^{commit}" >/dev/null
git diff --quiet "$FREEZE_COMMIT" -- \
  pocs/001-window-events-liveness/observer.lua \
  pocs/001-window-events-liveness/correlation.lua \
  pocs/001-window-events-liveness/trace.lua \
  pocs/001-window-events-liveness/private_export.lua \
  "$FIXTURE_SUBTREE/Sources" "$FIXTURE_SUBTREE/Resources" \
  "$FIXTURE_SUBTREE/scripts" "$FIXTURE_SUBTREE/Tests"
{ sw_vers; uname -m; hs -c 'print(hs.processInfo.version)'; git branch --show-current; git rev-parse HEAD; git rev-parse "$FREEZE_COMMIT"; git status --porcelain; } > "$RUN_DIR/environment.txt"
chmod 600 "$RUN_DIR/environment.txt"
require_mode "$RUN_DIR/environment.txt" 600

# Static build only; it creates no fixture process, socket, IPC request, or window.
"$ROOT/$FIXTURE_SUBTREE/scripts/build-fixture.sh"
test -x "$FIXTURE" && test -x "$FIXTURECTL"
```

`hs -c 'print(hs.processInfo.version)'` is only a read-only version query. If
unavailable, record that fact privately and abort before stopping legacy. Do not
substitute a differently built artifact.

### 2. Install abort restoration, launch without creating, then stop legacy/start observer

Before the following console actions, paste the shell trap block. Its observer
snippets are **instructions for the approved human to enter in the Hammerspoon
console**, not shell commands. The console responses must be reduced to the
listed safe booleans/counts; do not inspect or print trace tables.

```sh
cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  # Stop/export first if it was loaded; the console commands are idempotent.
  # If the console is unavailable, leave private evidence intact and continue
  # with fixture shutdown and legacy restoration.
  if [ "$FIXTURE_STARTED" = 1 ] && [ -n "$FIXTURE_PID" ] && kill -0 "$FIXTURE_PID" 2>/dev/null; then
    if [ -S "$RUN_DIR/poc001-fixture.sock" ]; then
      "$FIXTURECTL" "$RUN_DIR" shutdown req-abort fixture-abort-001 >/dev/null 2>&1 || kill "$FIXTURE_PID" 2>/dev/null || true
    else
      kill "$FIXTURE_PID" 2>/dev/null || true
    fi
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  # Human must execute the documented observer stop/export and legacy restart
  # console lines even on an abort. This trap never deletes evidence.
  if [ "$NORMAL_COMPLETE" != 1 ]; then
    printf '%s\n' "ABORT: retain $RUN_DIR; stop/export observer and restore legacy now" >&2
  fi
  exit "$status"
}
trap 'exit 130' INT TERM
trap cleanup EXIT

# Launch exactly once in absolute-clock mode. Do not send create yet.
export POC001_FIXTURE_CLOCK_KIND=mach_absolute
POC001_FIXTURE_RUN_DIR="$RUN_DIR" "$FIXTURE" &
FIXTURE_PID=$!
FIXTURE_STARTED=1
```

Await `run_started` and `socket_ready`, then verify `trace.ndjson` and the
socket are each `0600`. The approved operator uses a redacting marker waiter:
it accepts only complete JSON records, compares only `event` and `sample_id`,
and prints only `marker observed: <name>`. It uses a fixed timeout but no
`sleep`, retry, or inspection/printing of records. A timeout aborts the one
sample. **Do not create the fixture at this point.**

In the Hammerspoon console, stop the existing legacy object and verify it is
stopped before loading anything else:

```lua
local legacy = assert(spoon["10bucks"])
legacy:stop()
assert(legacy.started == false)
print("legacy_stopped=true")
```

The operator must also verify, using the legacy object's existing status or
handles without loading any POC code, that its watcher/reconciliation timer,
bar timer, and hotkeys are absent. If that cannot be verified, abort. Set
`LEGACY_STOPPED=1` in the shell only after that check.

Load the observer directly from the absolute frozen repository path, then start
it exactly once. Do not change Hammerspoon init/load paths and do not reload:

```lua
local root = "/ABSOLUTE/PATH/TO/10bucks" -- replace privately; do not print it
package.path = root .. "/pocs/001-window-events-liveness/?.lua;" .. package.path
-- Reload only observer dependencies from the frozen POC path, not stale console modules.
package.loaded.trace = nil
package.loaded.lifecycle = nil
package.loaded.ownership = nil
package.loaded.private_export = nil
package.loaded.correlation = nil
POC001_OBSERVER = assert(loadfile(root .. "/pocs/001-window-events-liveness/observer.lua"))()
assert(POC001_OBSERVER:start())
print("observer_started=true")
```

Before loading, the approved operator replaces the two quoted placeholder
values in the console snippets with the private absolute values of `ROOT` and
`OBSERVER_EXPORT`. Do not use a relative path or modify Hammerspoon init/load
paths. This keeps the observer source/export boundary explicit without relying
on an environment change to an already-running Hammerspoon process.

Set the exact sample once and arm exactly generation `1` once. This is the
only correlation arm:

```lua
POC001_OBSERVER.trace:set_sample("fixture-observer-correlation-smoke-001")
assert(POC001_OBSERVER:arm_fixture_correlation(1))
print("sample_set_and_generation_armed_once=true")
```

### 3. Create once and await only approved facts

After legacy is stopped, the observer is started, and the sample/generation is
set exactly once, create the sole fixture exactly once, capturing the response
privately:

```sh
"$FIXTURECTL" "$RUN_DIR" create req-001 fixture-correlation-create-001 > "$RUN_DIR/create-response.json"
chmod 600 "$RUN_DIR/create-response.json"
require_mode "$RUN_DIR/create-response.json" 600
```

The response is **alias-only for correlation**: the local analyzer may read
`correlation_alias`, while the close control uses `fixture_token` privately. Do
not display either. Await both (a) `fixture_create_visible_completed` for
`fixture-correlation-create-001`, and (b) this safe console status only:

```lua
local s = POC001_OBSERVER:status()
assert(s.correlation.map_count == 1 and s.correlation.armed == true)
print("observer_correlation_map_count=1")
```

Do not print the alias. A visible fixture or a map count is not liveness,
readiness, or authority evidence.

### 4. Controlled close, destruction candidates, finish, stop/export, restore legacy

Extract the fixture control token without printing it; issue exactly one close:

```sh
FIXTURE_TOKEN="$(python3 - "$RUN_DIR/create-response.json" <<'PY'
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))
token = row.get("fixture_token")
alias = row.get("correlation_alias")
if row.get("status") != "accepted" or not isinstance(token, str) or not token.startswith("fixture-win-") or not isinstance(alias, str):
    raise SystemExit(1)
print(token)
PY
)"
"$FIXTURECTL" "$RUN_DIR" close req-002 fixture-correlation-close-001 "$FIXTURE_TOKEN" > "$RUN_DIR/close-response.json"
chmod 600 "$RUN_DIR/close-response.json"
unset FIXTURE_TOKEN
require_mode "$RUN_DIR/close-response.json" 600
```

Await fixture `native_close_completed` for the close sample. Then await the
observer export facts for **both** direct and filter controlled destruction
candidates; each must carry the retained alias. Candidate-only facts do not
select destruction authority. After they arrive, finish correlation once:

```lua
assert(POC001_OBSERVER:finish_fixture_correlation())
local s = POC001_OBSERVER:status()
assert(s.correlation.map_count == 0 and s.correlation.armed == false)
assert(s.active_timers == 0 and s.window_effects == 0 and s.callbacks.open == 0)
print("correlation_finished_map_count=0,timers=0,effects=0,callbacks_open=0")
assert(POC001_OBSERVER:stop())
POC001_OBSERVER:export("/ABSOLUTE/PRIVATE/RUN_DIR/observer-export.json") -- replace privately
print("observer_stopped_and_exported=true")
```

The private replacement export path must be exactly `OBSERVER_EXPORT` inside
`RUN_DIR`. Verify the export is owner `0600`. **Restart legacy before any
analysis**, only after the observer has stopped/exported:

```lua
local legacy = assert(spoon["10bucks"])
legacy:start()
assert(legacy.started == true)
print("legacy_restarted=true")
```

Only now shut down the fixture and wait for it:

```sh
"$FIXTURECTL" "$RUN_DIR" shutdown req-003 fixture-correlation-shutdown-001 > "$RUN_DIR/shutdown-response.json"
chmod 600 "$RUN_DIR/shutdown-response.json"
wait "$FIXTURE_PID"
! kill -0 "$FIXTURE_PID" 2>/dev/null
! test -e "$RUN_DIR/poc001-fixture.sock"
require_mode "$RUN_DIR/trace.ndjson" 600
require_mode "$OBSERVER_EXPORT" 600
```

## Local redacting analyzer and acceptance

Run the analyzer only after legacy is restarted and the fixture is shut down.
Create it in the `0700` run directory, then run it with `--no-sleep`; it writes
only a `0600` aggregate and never prints raw input. It joins exact full aliases
only, rejects missing/duplicate/malformed values, and uses the frozen
quotient/remainder conversion of fixture absolute ticks/timebase against each
candidate's `absolute_ns`.

```sh
cat > "$RUN_DIR/analyze.py" <<'PY'
import json, os, re, stat, sys
prefix = "poc001-corr-sha256-"
alias_re = re.compile(r"^" + prefix + r"[0-9a-f]{64}$")
sensitive = {"fixture_token", "correlation_token", "raw_ax", "raw_id", "pid", "title", "path", "url", "bundle_id"}
def fail(reason):
    raise ValueError(reason)
def load_json(path):
    with open(path, encoding="utf-8") as f: return json.load(f)
def lines(path):
    with open(path, encoding="utf-8") as f: return [json.loads(x) for x in f if x.strip()]
def one(rows, label):
    if len(rows) != 1: fail(label + "_count")
    return rows[0]
def alias(value, label):
    if not isinstance(value, str) or not alias_re.fullmatch(value): fail(label)
    return value
def ns(row):
    if row.get("clock_kind") != "mach_absolute": fail("fixture_clock_not_absolute")
    ticks, numer, denom = row.get("ticks"), row.get("timebase_numer"), row.get("timebase_denom")
    if any(not isinstance(x, int) or isinstance(x, bool) or x < 0 for x in (ticks, numer, denom)) or numer == 0 or denom == 0: fail("invalid_timebase_or_ticks")
    return (ticks // denom) * numer + ((ticks % denom) * numer) // denom
def mode(path, expected):
    if stat.S_IMODE(os.stat(path).st_mode) != expected: fail("unsafe_mode")
def main(run, no_sleep):
    if not no_sleep: fail("sleep_not_refused")
    fixture, observer, response = lines(run + "/trace.ndjson"), load_json(run + "/observer-export.json"), load_json(run + "/create-response.json")
    events, status = observer.get("events"), observer.get("status")
    if not isinstance(events, list) or not isinstance(status, dict): fail("invalid_observer_export")
    # Fixture records necessarily contain the private close-control capability;
    # it is parsed but never copied to output. Correlation raw values remain forbidden.
    for row in fixture:
        if not isinstance(row, dict) or {"correlation_token", "raw_ax", "raw_id", "pid", "title", "path", "url", "bundle_id"}.intersection(row): fail("fixture_sensitive_field")
    for row in events:
        if not isinstance(row, dict) or sensitive.intersection(row): fail("observer_sensitive_field")
    fa = alias(response.get("correlation_alias"), "fixture_response_alias")
    create = one([e for e in fixture if e.get("event") == "create_requested"], "fixture_create")
    if alias(create.get("correlation_alias"), "fixture_trace_alias") != fa: fail("fixture_alias_inconsistent")
    observed = one([e for e in events if e.get("marker") == "correlation_observed"], "observer_creation")
    oa = alias(observed.get("correlation_alias"), "observer_alias")
    if fa != oa: fail("alias_mismatch")
    constructs = [e for e in events if e.get("marker") == "query_attempt" and e.get("query") == "correlation_window_element_construction"]
    reads = [e for e in events if e.get("marker") == "query_attempt" and e.get("query") == "correlation_ax_identifier_read"]
    if len(constructs) != 1 or len(reads) != 1: fail("identifier_query_count")
    close = one([e for e in fixture if e.get("event") == "native_close_completed" and e.get("origin") == "ipc"], "fixture_native_close")
    base = ns(close)
    candidates = [e for e in events if e.get("marker") == "destruction_candidate" and e.get("correlation_alias") == fa]
    by_source = {source: [e for e in candidates if e.get("source") == source] for source in ("filter", "direct_ax")}
    if any(len(v) != 1 for v in by_source.values()): fail("controlled_candidate_count")
    latencies = {}
    for source, rows in by_source.items():
        value = rows[0].get("absolute_ns")
        if not isinstance(value, int) or isinstance(value, bool) or value < base: fail("negative_or_order_invalid")
        latencies[source] = value - base
        if latencies[source] > 1_000_000_000: fail("destruction_latency_over_1000ms")
    durations = [e.get("duration_ms") for e in events if e.get("marker") == "callback_exit"]
    if not durations or any(not isinstance(x, (int, float)) or x > 100 for x in durations): fail("callback_max_over_100ms")
    if status.get("lifecycle") != "stopped" or status.get("callbacks", {}).get("open") != 0 or status.get("steady_global_queries") != 0: fail("observer_cleanup_or_query_budget")
    finished = one([e for e in events if e.get("marker") == "correlation_finished"], "correlation_finished")
    if finished.get("correlation_map_count") != 0 or finished.get("correlation_armed") is not False: fail("correlation_cleanup")
    for name in ("trace.ndjson", "create-response.json", "close-response.json", "shutdown-response.json", "observer-export.json"):
        mode(run + "/" + name, 0o600)
    return {"pass": True, "alias_equal": True, "identifier_constructions": 1, "identifier_reads": 1, "map_count_before_close": 1, "map_count_after_finish": 0, "callback_max_ms": max(durations), "candidate_latency_ns": latencies, "sleep_observed": False}
try:
    result = main(sys.argv[1], sys.argv[2:] == ["--no-sleep"])
except Exception as e:
    result = {"pass": False, "reason": str(e)}
with open(sys.argv[1] + "/analysis.json", "w", encoding="utf-8") as f: json.dump(result, f, sort_keys=True); f.write("\n")
os.chmod(sys.argv[1] + "/analysis.json", 0o600)
sys.exit(0 if result["pass"] else 1)
PY
chmod 700 "$RUN_DIR/analyze.py"
python3 "$RUN_DIR/analyze.py" "$RUN_DIR" --no-sleep
require_mode "$ANALYSIS" 600
```

Before accepting the result, verify from the stopped export: `callbacks.open=0`,
observer lifecycle is `stopped`, and the analyzer's zero correlation map result
matches the pre-stop safe console check of zero timers/effects/map. Also verify
no observer/fixture process or socket remains and all named private files retain
the required modes. The analyzer rejects a nonzero global steady query count,
sensitive keys, invalid/duplicate aliases, missing candidates, and all invalid
clock comparisons; its output contains no raw correlation or window identity.

A pass says only that this one controlled correlation smoke met its frozen
instrumentation contract. It does **not** establish a p95, choose filter/direct
AX authority, prove destruction, liveness, readiness, or next-key service.

## Abort and evidence preservation

Abort immediately for any failed preflight, unexpected second window, user
interaction, timeout, duplicate callback/read/alias, permission mismatch,
prohibited query, sleep, privacy leak, analyzer refusal, or cleanup mismatch.
Do not create another fixture, re-arm a generation, reload Hammerspoon, or
retry. The shell trap attempts only fixture shutdown/termination and preserves
the private directory. The human must then execute the same observer
stop/export (when possible) and legacy-restart console lines, recording whether
each succeeded. If any restoration fails, keep evidence and report the failure;
do not remove files or claim a result.

After a normal or aborted run, retain the private directory until the human has
recorded a redacted aggregate. Remove response files and the directory only
with explicit human direction after that record; never commit them.
