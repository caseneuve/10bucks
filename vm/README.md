# macOS functional-test VM

Host-side Tart helpers. These do not load 10bucks or alter the host's Hammerspoon.
Requires macOS/Apple Silicon, the installed Tart binary, Python 3, and the existing
SSH key. Paths default to `$HOME/.tart`; override `TART_BIN`, `VM_SSH_KEY`, or
`VM_KNOWN_HOSTS` if necessary.

## Launch from this checkout

```sh
./vm/run                         # live VM desktop; foreground Tart process
./vm/run --detach                # live desktop, return to caller; no Terminal.app
./vm/run --headless --detach     # no desktop window and no Terminal.app
./vm/ssh 'sw_vers; csrutil status'
./vm/hs 'return hs.accessibilityState()'
```

Default VM: `10bucks-lab`. Supply a name to `vm/run`; set `TENBUCKS_VM` for
`vm/ssh` and `vm/hs`. Do not use two operators against the same VM. The helpers
never stop an existing VM, delete images, enable SIP, or bypass login/lock.
`vm/run` refuses names containing `base` to protect reusable images.

Detached launches record `tart.log` and `tart.pid` under `vm/results/VM_NAME/`.
A PID/launch success is **not guest readiness**. DHCP can return a stale lease
before SSH is listening; Hammerspoon can start later still. `vm/hs` bounds the
whole SSH/IPC request to 15 seconds. A timeout is a harness/readiness failure,
not evidence of a 10bucks bug. SSH commands themselves are caller-bounded.

Shutdown cleanly through the guest, then verify Tart reports stopped:

```sh
./vm/ssh 'sudo -n /sbin/shutdown -h now'
# SSH may report disconnection; verify completion separately:
"$HOME/.tart/tool/tart.app/Contents/MacOS/tart" get 10bucks-lab --format json
```

Do not force-kill Tart by a stored PID: it may be stale/reused. The foreground
mode gives a test runner direct process ownership; detached mode is for manual
work and exploration. A future acceptance runner should own launch/readiness,
cleanup acknowledgement, and a fixed total deadline in one process.

## Shares and source isolation

- Checkout: `/Volumes/My Shared Files/10bucks` (read-only).
- Results: `/Volumes/My Shared Files/results` (writable, host `vm/results/VM_NAME`).
- Guest Spoon link points into the checkout. Guest init currently loads only
  `hs.ipc`; 10bucks does not start automatically.

The old launcher also mounted installation `setup` artifacts; these are not
needed by the configured guest. Finder opened Terminal because the old launcher
was a `.command` file, not because Tart requires a terminal.

Read-only sharing does **not** freeze host edits. Freeze/hash the complete
executed artifact set before loading a candidate; do not edit it during a run.
For an automated suite, mount an immutable per-run source snapshot instead of
the live checkout. Preserve failing results; do not overwrite them on a retry.

## Verified investigation — 2026-10-11

- `10bucks-lab` was already running; left under its existing operator's launcher.
  Fresh guest check: macOS 26.6.2 (25G83), SIP **enabled**, Accessibility granted,
  unlocked, one display; no 10bucks loaded. This supersedes the setup handoff's
  stopped/SIP-disabled lab facts.
- `10bucks-functional-base` is still the earlier SIP-disabled image. Its
  disposable clone `10bucks-run-launch-probe-20261011` booted headlessly, with
  SSH and Hammerspoon IPC, on two launches. The second used `vm/run --detach`.
- On the first clone boot, independently read native frame/focus of its sole
  Terminal window, changed its frame, confirmed focus and frame readback, then
  restored and confirmed the original frame. No manager loaded.
- Host/guest `core.lua` SHA-256 matched. Guest Lua 5.5.1 ran `tests/run.lua`:
  **212 passed; 0 failed**. Log: `vm/results/10bucks-run-launch-probe-20261011/pure-lua-tests.log`.
- Startup IPC timed out before becoming ready. AppleScript `do script` also
  timed out; it was stopped without classifying this as platform behavior.
  Automation permission/dialog is a hypothesis, not a verified cause.
- Shell syntax, ShellCheck, and diff whitespace checks passed.

These are harness observations, **not** acceptance of the proposed manager or
host performance. VM display semantics are not built-in-display fidelity.

## Next: executable behavioral acceptance

The desired oracle comes from `docs/invariants.md`, not current implementation
internals. Keep pure reducer/sequence tests; add native tests that can catch a
correct reducer whose effects or event routing are wrong.

Proposed minimal structure: `functional-tests/` with a host runner, a guest Lua
controller loaded by IPC, and a small owned native fixture app. The fixture
should create/close/minimize/focus named test windows without AppleScript
Automation permission; the controller observes native AX/frame/focus/Space
facts separately from candidate state. Test-only sampling is bounded and does
not authorize production polling. Fixture behavior and eligibility must be
proved before relying on them.

First scenario (COL-002, COL-005, WIN-005, FOCUS-004, FOCUS-006):

1. Fresh SIP-enabled disposable guest, verified unlocked/settings/permissions.
2. Load one frozen candidate; create fixture A; assert native full-width frame.
3. Create B; assert A left/B right, B actually focused.
4. Close B through the fixture's normal native path; assert A full-width and
   actually focused; issue navigation and assert no stale dead target.
5. Repeat as a combined stack → create → columns → focus-left/right → close
   sequence, asserting after each action. Add minimized-bootstrap and overlapping
   hide/minimize sequences next.

Use explicit bounded eventual assertions, not arbitrary sleeps; fix deadlines
before the run and retain timeouts. Native frames/focus are the primary oracle.
Candidate membership/selection/event traces explain failures and support stable
order/retained-slot assertions, but cannot alone prove visible success. Drive
real hotkeys for end-to-end binding tests; direct command invocation can be a
separate orchestration test, not equivalent evidence.

Record source/helper/fixture hashes, environment/settings, action timestamps,
native outcomes, candidate primitive traces, errors, and cleanup results. A VM
can establish guest functional behavior. Supported-host latency and visual bar/
Mission Control fidelity remain separately measured on the physical Mac.

**SIP-enabled base created, 2026-10-11:** with operator approval, the lab was
cleanly shut down and cloned into `10bucks-functional-sip-base-20261011`.
The new base is stopped; the old images are retained. Its disposable clone
`10bucks-run-fixture-proof-20261011` freshly reported SIP enabled, Accessibility
access, an unlocked session, Secure Input off, and no manager loaded.
The owned fixture and its no-manager proof controller now exist under
`functional-tests/fixture/`; native proof is pending. The candidate acceptance
runner/driver is not implemented yet. Do not relabel the older SIP-disabled base.
