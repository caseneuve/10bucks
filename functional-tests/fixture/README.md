# Owned AppKit fixture

## Proof checkpoint — 2026-10-11

First frozen native proof failed before any window creation. The controller used
`hs.json.encode` on a scalar alias; Hammerspoon accepts tables only. The failed
publication also advanced its sequence, preventing graceful cleanup. This is a
reviewed harness/API defect, not macOS or candidate evidence. The owned task was
terminated and the disposable VM was independently verified stopped; failure
artifacts remain under ignored `vm/results/`.

The repaired controller explicitly quotes the closed A/B alias alphabet and
advances sequence only after atomic publication. Deterministic table-only encoder
and publication-failure checks passed; repaired source review is READY. Native
rerun is pending operator approval, with unchanged deadlines and a new manifest.

`run-proof.py` snapshots/hashes executed artifacts, starts the guest controller,
monitors within 40s, then owns a separate 15s shutdown/verification budget. It
requires an already-owned `TENBUCKS_VM=10bucks-run-fixture-proof-*` guest and always
shuts that guest down. It does not clone/boot a VM or load a candidate.

Build only: `./functional-tests/fixture/build.sh` (caller timeout <=120 seconds).
Produces ignored `build/Fixture.app`; does not launch or sign/install it.
Requires macOS SDK/Swift compiler. Native eligibility and behavior are **unverified**.

The lead/native operator alone may launch the executable inside the disposable
unlocked guest, with `--run NONCE --control-dir /absolute/new/path`.
Nonce is 1–128 alphanumeric/underscore/hyphen characters. The fixture creates a
new directory mode 0700; its existing parent must be private and guest-local.
Never put control files/native identities in the repository or export them.
No initial windows. Closing the last window does not quit the application.

## Serialized atomic mailbox

One controller, one outstanding request, no concurrent writers. Wait for the
initial `ack.json` (`operation: ready`, `sequence: 0`) before sending requests.
Write UTF-8 JSON to a temporary file **in the control directory**, then atomically
rename it to `request.json`. Maximum 8192 bytes. Exactly these keys:

```json
{"run":"the-cli-nonce","sequence":1,"operation":"create","alias":"A"}
```

Sequences start at 1 and must be exactly previous accepted-envelope sequence + 1.
Operations: `create`, `focus`, `close` with alias `A` or `B`; `quit` with JSON null
alias. Only create once per alias per process; closed aliases cannot be reused.
`focus` is solely for fixture control proof without the manager, **not** scenario
focus repair. Create uses `orderFront(nil)` without activation/key-focus requests;
the candidate must provide admission focus. Close uses `performClose(nil)` and
never explicitly focuses the survivor. AppKit/native fallback behavior must be
observed independently, not inferred from these choices. Closing releases the
fixture's NSWindow reference while preserving primitive alias/window-number data.

The main thread claims each request as `processing.json`, processes it, explicitly
removes its claim, then atomically replaces `ack.json` (also before quit terminates).
Every malformed/normal outcome cleans a successfully claimed file. Claim-removal
failure prints an error and exits nonzero without acknowledging or continuing;
a failed claim does not authorize removal of an existing `processing.json`. Acknowledgements contain `run`, `sequence`,
`operation`, `alias`, `accepted`, `pid`, `windowNumber`, and optional stable `error`.
Window number is null before creation; subsequent close/focus acknowledgements
retain the created number for exact **app-local** resource joining. Never infer
identity across process/window-number reuse. Ready/quit have null alias/number.

Malformed JSON/envelopes or wrong run/sequence do not advance sequence; their
rejection ack reports the current sequence with operation `invalid` and null
alias. Structurally valid matching envelopes consume the sequence even when
operation/alias or lifecycle validation fails; correlate their rejection by
sequence. Do not blindly retry an action after an uncertain acknowledgement.
Ack means **processed**, not actual native focus, destruction, frame convergence,
or candidate delivery. Independently retain/observe the exact native resource.
Ack write failure exits nonzero. Crash recovery/replay is unsupported; preserve
failed artifacts and begin another explicitly authorized run with a fresh nonce
and directory. Controller owns bounded waits, termination checks and cleanup.

A 50ms main-thread timer polls only this private test mailbox, never native
windows or candidate state. No sockets, AppleScript, shell/arbitrary execution,
window discovery, manager mutation, minimize/hide/fullscreen controls, or host
native actions. This deliberately does not copy the old focus-stealing fixture.

## Guest-only no-manager proof controller

`proof.lua` returns a controller when loaded with `dofile`; loading alone has no
native effects. Only the lead may run this in an unlocked, disposable guest with
Hammerspoon Accessibility permission and **no window manager running**:

```lua
fixtureProof = dofile('/guest/checkout/functional-tests/fixture/proof.lua')
fixtureProof.start({executable='/guest/Fixture.app/Contents/MacOS/Fixture',
  controlDir='/private/guest-parent/new-control', run='unique-run-nonce',
  resultPath='/private/guest-parent/new-result.json'})
-- Later: fixtureProof.status(); fixtureProof.stop()
```

Supply the exact reviewed executable, fresh nonce/new paths, existing private
parents, and no concurrent mailbox writer. Result must be outside the control
directory. The controller retains only the task it directly launches and its PID;
never targets another process for termination. Status/results do not export PID,
window numbers, titles, stdout/stderr, raw AX values or unrelated window data.
Owned native frames, alias flags, monotonic elapsed times and stable error codes
are recorded. Paths and artifacts stay guest-local.

Sequence: ready → create/join A by acknowledged PID + app-local window number →
verify standard AX window and settable position/size → explicit focus A confirmed
by global native window equality → create/join/focus B → register and inspect the
exact B AX destruction watcher → normal close B → exact retained B invalidity OR
matching destruction, A valid and task alive → quit acknowledgement → normal task
exit and no request/processing files. No survivor focus repair. Each native/ack
step has a fixed 3-second deadline. 50ms asynchronous mailbox/native observations,
no blocking sleeps. At 24 seconds proof enters cleanup; graceful quit gets up to
3 seconds, then only the retained task receives SIGTERM. Finish by 29 seconds,
recording cleanup separately; unresolved task shutdown fails, never becomes pass.
`stop()` enters the same asynchronous cleanup, preserving the first error.
All expected cleanup conditions, including normal exit and quit ack, are required
for pass; forced termination always fails. Inspect `resultWriteFailed` in status
if the result cannot be atomically written. No automatic retry.

The negative frame check uses the same tolerance predicate on an owned native
frame and an intentionally wrong expected x-coordinate (+100 points): the wrong
expectation must fail. It checks the oracle, **not** expected tiling geometry or
frame stability. Invalidity is counted only on explicit `false`, not nil/error or
absence from enumeration. No malformed/replay exercise in this first proof.

**Limits:** syntax/source checks are not native evidence. Eligibility, focus,
observer delivery, close, and process cleanup remain unverified until the lead
runs and reviews the guest result. Hammerspoon timers cannot interrupt synchronous
AX/API calls or a stalled event loop: the <=30s bound is the controller deadline,
not a hard process watchdog.

Fixed outer invocation/monitor procedure (lead only; no automatic rerun):
1. Start one proof and record host monotonic start time. The guest controller has
   a **<=29-second** deadline, including cleanup. Never use a blocking IPC wait
   for the sequence.
2. Host polls the private final result/controller status using individually
   bounded guest IPC calls, with an absolute **<=40-second** deadline from start.
   Require final result, `pass=true`, normal expected cleanup, and no retained
   running task; missing result or result-write failure is failure, not success.
3. On failure/incomplete result, use a **separate <=15-second cleanup phase**:
   call `fixtureProof.stop()` and verify `ownedTaskRunning=false` and completion
   callback receipt. This targets only its retained task, including an unresolved
   handle retained after deadline. If guest IPC/event-loop/task cleanup cannot be
   verified within that bound, shut down the exclusively owned disposable VM and
   verify shutdown within the same cleanup bound; otherwise report unresolved
   cleanup for operator intervention. Never kill a process located by exported
   PID or act on another VM. Preserve the original failure and guest artifacts.
   This phase is failure containment, not extra proof time or permission to rerun.

Cleanup drains pending acknowledgements even after the task stops and waits for
its completion callback until the absolute guest deadline. At that deadline any
still-running retained task receives SIGTERM before finalization; unresolved
shutdown/callback state is explicitly reported and its task handle retained.
Result-write failure changes status `pass` to false. This proof models only
this owned AppKit app, not Ghostty or general platform lifecycle guarantees.
