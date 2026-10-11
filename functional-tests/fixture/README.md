# Owned AppKit fixture

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
