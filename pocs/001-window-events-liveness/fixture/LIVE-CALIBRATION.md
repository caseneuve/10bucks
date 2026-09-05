# POC-001 fixture-only live calibration — one-sample operator guide

**Status: proposed; requires explicit human approval before use.** This guide
prepares exactly one disposable **warm** fixture smoke sample. It is not an
authorization to build, launch, send IPC, change Hammerspoon, or run any POC.
It is intentionally outside the 30-warm/5-cold volume run and outside the
fixture--observer correlation experiment.

## Scope and frozen boundary

- **Hypothesis:** for the exact fixture window, public AppKit's first
  `windowDidChangeOcclusionState` callback with the `.visible` bit arrives
  after `create_requested`; one queued fixture main-queue closure is serviced;
  and the same fixture window reaches `windowWillClose` after an IPC close.
  This is fixture-local timing only.
- **Not proved:** liveness, unobscured pixels, AX readiness, Spaces, admission,
  Hammerspoon delivery, destruction authority, representative-app behavior, or
  any macOS behavior beyond this one fixture observation. No observer is
  loaded and no correlation token is used.
- **Environment/build freeze:** before approval, the human approver records the
  current `sw_vers`, `uname -m`, `swiftc --version`, branch, full `HEAD`, and
  clean-tree status in the private run record. The fixture source/build
  checkpoint is `9a3678074367610c11711ea7d190c83bf7879032`; its build inputs
  (`Sources`, `Resources`, `scripts`, and `Tests`) must be unchanged
  (`git diff --quiet <checkpoint> -- pocs/001-window-events-liveness/fixture/{Sources,Resources,scripts,Tests}`).
  The build used for the run must be made from that unchanged subtree and its
  commit recorded; do not substitute an unrecorded artifact.
- The fixture window will visibly appear, then disappear. Its only create
  presentation call is `orderFrontRegardless()`. No code touches or focuses an
  unrelated window. Legacy 10bucks remains running: this guide neither loads
  nor modifies Hammerspoon and involves no Hammerspoon observer.

The single sample is deliberately named `fixture-*-warm-001`. Do not loop,
retry, add a cold sample, collect observer data, or claim a percentile from it.

## Preconditions (human gate)

The human approver must authorize this exact guide, one local unsigned fixture
build, and one launch. Do **not** proceed if any item below is false:

1. The fixture pure tests and static build-layout check are green for the
   frozen source checkpoint; the bundle exists at the path below. Building is a
   separate approved action and is not part of this smoke sequence.
2. `git status --porcelain` is empty, the fixture subtree matches the frozen
   checkpoint, and the recorded commit/build artifact are the ones approved.
3. The operator can visually observe one disposable fixture window appear and
   disappear without interacting with other windows. There is no representative
   app in this run.
4. The operator accepts that all trace, response, and environment files remain
   local in a new owner-private directory. Never paste a token, trace line,
   response, title, path, or raw data into chat, a ticket, or git.

## Exact one-sample sequence

Run the following in the repository root **only after approval**. It starts the
fixture executable directly; it does not use `open`, `hs`, `osascript`, or any
Hammerspoon command.

```sh
set -eu
umask 077
ROOT="$PWD"
FIXTURE_COMMIT=9a3678074367610c11711ea7d190c83bf7879032
FIXTURE="$ROOT/pocs/001-window-events-liveness/fixture/build/POC001Fixture.app/Contents/MacOS/POC001Fixture"
FIXTURECTL="$ROOT/pocs/001-window-events-liveness/fixture/build/POC001Fixture.app/Contents/MacOS/poc001-fixturectl"

test "$(git rev-parse --is-inside-work-tree)" = true
git diff --quiet "$FIXTURE_COMMIT" -- pocs/001-window-events-liveness/fixture/{Sources,Resources,scripts,Tests}
test -x "$FIXTURE" && test -x "$FIXTURECTL"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/poc001-fixture.XXXXXX")"
chmod 700 "$RUN_DIR"
test "$(stat -f %u "$RUN_DIR")" = "$(id -u)"
test "$(stat -f %Lp "$RUN_DIR")" = 700
{ sw_vers; uname -m; swiftc --version; git branch --show-current; git rev-parse HEAD; git status --porcelain; } > "$RUN_DIR/environment.txt"
chmod 600 "$RUN_DIR/environment.txt"

POC001_FIXTURE_RUN_DIR="$RUN_DIR" "$FIXTURE" &
FIXTURE_PID=$!
```

The operator now waits for `run_started` and `socket_ready` without displaying
the trace. Use this marker waiter; it validates newline-delimited JSON and
prints only the requested marker/status, never a token or raw trace field.

```sh
await_marker() {
  python3 - "$RUN_DIR/trace.ndjson" "$1" "$2" <<'PY'
import json, os, sys, time
path, wanted, sample = sys.argv[1:]
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    try:
        with open(path, encoding="utf-8") as trace:
            for line in trace:
                row = json.loads(line)
                if row.get("event") == wanted and row.get("sample_id") == sample:
                    print("marker observed: " + wanted)
                    raise SystemExit(0)
    except FileNotFoundError:
        pass
    time.sleep(0.05)
print("marker timeout: " + wanted, file=sys.stderr)
raise SystemExit(1)
PY
}
await_marker run_started startup
await_marker socket_ready startup
test "$(stat -f %u "$RUN_DIR/trace.ndjson")" = "$(id -u)"
test "$(stat -f %Lp "$RUN_DIR/trace.ndjson")" = 600
test "$(stat -f %u "$RUN_DIR/poc001-fixture.sock")" = "$(id -u)"
test "$(stat -f %Lp "$RUN_DIR/poc001-fixture.sock")" = 600
```

Issue exactly these four requests, in this order. Responses are captured only
in the `0700` directory. The fixture token is extracted into a shell variable
without printing it. The orchestrator's marker checks expose only marker names.

```sh
"$FIXTURECTL" "$RUN_DIR" create req-001 fixture-create-warm-001 > "$RUN_DIR/create-response.json"
chmod 600 "$RUN_DIR/create-response.json"
await_marker fixture_create_visible_completed fixture-create-warm-001

"$FIXTURECTL" "$RUN_DIR" probe_pending_work req-002 fixture-probe-warm-001 > "$RUN_DIR/probe-response.json"
chmod 600 "$RUN_DIR/probe-response.json"
await_marker pending_work_serviced fixture-probe-warm-001

FIXTURE_TOKEN="$(python3 - "$RUN_DIR/create-response.json" <<'PY'
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))
token = row.get("fixture_token", "")
if row.get("status") != "accepted" or not token.startswith("fixture-win-"):
    raise SystemExit(1)
print(token)
PY
)"
"$FIXTURECTL" "$RUN_DIR" close req-003 fixture-close-warm-001 "$FIXTURE_TOKEN" > "$RUN_DIR/close-response.json"
chmod 600 "$RUN_DIR/close-response.json"
unset FIXTURE_TOKEN
await_marker native_close_completed fixture-close-warm-001

"$FIXTURECTL" "$RUN_DIR" shutdown req-004 fixture-cleanup-001 > "$RUN_DIR/shutdown-response.json"
chmod 600 "$RUN_DIR/shutdown-response.json"
wait "$FIXTURE_PID"
```

The human action expected is ideally **none** beyond observing that one
unrelated-to-your-work disposable fixture window appears and disappears. Do not
click it, close it manually, switch Spaces, or interact with another window.

## Evaluate one smoke sample only

The operator may privately calculate only the named trace deltas from
`elapsed_ticks` with the recorded timebase, or use a redacting local summary
that outputs pass/fail/counts only. Keep tokens and raw records private.

- `fixture_create_visible_completed - create_requested`: compare the one value
  with 100 ms as a diagnostic only. The frozen warm-create threshold is **p95
  <= 100 ms over n=30**; **n=1 cannot claim that p95 or a warm-create pass**.
- `native_close_completed - close_requested`: the single value must be **<=
  1,000 ms**. It remains a fixture-local close diagnostic, not the POC's
  observer destruction-confirmation gate.
- `pending_work_serviced - pending_work_requested`: the single value must be
  **<= 100 ms max**. It does not establish the frozen p95 <= 50 ms threshold
  or general main-thread/Hammerspoon service.

Any missing, duplicate, late, out-of-order, wrong-sample, or user-origin close
is an abort/failure for this smoke sample. Do not rerun it ad hoc or change a
threshold.

## Stop, privacy, and cleanup

Abort immediately on a timeout, rejected command, unsafe owner/mode check,
trace/JSON failure, unexpected window interaction, privacy concern, more than
one fixture window, or any Hammerspoon/observer activity. Do not inspect or
print raw trace/response data to diagnose it. If the socket still exists, send
only the normal shutdown request (discarding its response); otherwise terminate
only the recorded fixture PID. Then wait for it:

```sh
if kill -0 "$FIXTURE_PID" 2>/dev/null; then
  "$FIXTURECTL" "$RUN_DIR" shutdown req-abort fixture-abort-001 >/dev/null 2>&1 || kill "$FIXTURE_PID"
fi
wait "$FIXTURE_PID" 2>/dev/null || true
```

After either normal completion or abort, verify all of the following without
querying any unrelated window: the fixture PID is gone (`! kill -0
"$FIXTURE_PID" 2>/dev/null`), `poc001-fixture.sock` is absent, the private
trace remains owner `0600`, and the operator saw the sole disposable fixture
window disappear. Delete private response files (which can contain tokens) and
the private run directory after the human has recorded a redacted result:

```sh
! kill -0 "$FIXTURE_PID" 2>/dev/null
! test -e "$RUN_DIR/poc001-fixture.sock"
test "$(stat -f %Lp "$RUN_DIR/trace.ndjson")" = 600
rm -f "$RUN_DIR"/*response.json
rm -rf "$RUN_DIR"
```

Commit only a redacted aggregate: frozen commit/environment, marker
pass/fail, three timing values or classifications, permissions/cleanup result,
and explicit statement that this was one fixture-only smoke sample. Never
commit the run directory, tokens, raw NDJSON, responses, screenshot, window
identity, or correlation data.
