# Native functional acceptance scenarios

The VM is the agent-owned testing environment: guest setup, native test actions,
diagnostics, retries and necessary lifecycle repairs are already authorized.
Do not stop to request approval for individual VM procedures. See `AGENTS.md`
for the standing ownership boundary, one-operator rule, evidence requirements
and separate host authority. Complete native scenarios are authoritative for
guest functional behavior; mock/unit passes do not replace them.

First executable scenario: `scenarios/columns_close_recovery.py`.
The runner and native guest driver are implemented. The first native scenario
passed in a fresh SIP-enabled clone on 2026-10-11: A full-width/focused → A left,
B right/focused → close B → A full-width/focused → next/previous callbacks.
Cleanup stopped candidate/fixture/VM and confirmed Tart exit. This accepts only
this narrow fixture flow, not broad app reliability, bar pixels or performance.
Earlier failed runs are retained; no deadlines were relaxed. Production Lua is
unchanged.

```sh
./functional-tests/run --headed --demo columns-close-recovery
```

This command clones the stopped SIP-enabled base, opens the guest desktop, runs
real candidate hotkeys and native frame/focus assertions, then stops the manager,
fixture and VM. `--demo` adds two-second action pauses for visibility; it is not a
latency benchmark. Without `--headed` the VM has no desktop window.
For debugging, `--keep-open` retains the owned VM after failure (the controller
still has its watchdog). Reuse it without another boot:

```sh
./functional-tests/run --headed --demo --reuse-debug VM_NAME columns-close-recovery
```

Reuse requires its recorded debug ownership and rejects an unresolved running
fixture. Stop it through the retained controller and verify its task exited before
reuse. The runner reloads guest Hammerspoon modules, snapshots new source into a separate
session, and leaves the VM running. Reused runs are marked **not cold acceptance**.
Do not edit a snapshot behind a running candidate. The fixture creates normal
foreground key windows; creation focus is an outcome check, not proof of manager
causation. Closing never explicitly focuses the survivor.

Artifacts remain in ignored `vm/results/10bucks-run-ft-*/`, with separate guest
trace and host summary, source hashes, environment and assertion samples.
Do not interpret a setup failure as a candidate behavioral result. Scenario
self-checks below validate the oracle only, not macOS/10bucks behavior.

## columns-close-recovery

Contracts: COL-002, COL-005, COL-007, STACK-002, LAY-003, WIN-005,
FOCUS-004, FOCUS-005, FOCUS-006.

| Step | Native assertion | Secondary assertion |
| --- | --- | --- |
| Create A | A fills independently computed usable area; A focused | managed aliases = A |
| Create B | A left half, B right half; B focused | managed aliases = A,B |
| Directional h/l | B→A→B actual focus; split frames unchanged | one callback per command; membership A,B |
| Previous managed twice | B→A→B actual focus; split frames unchanged | one callback per command |
| Cycle to stack | both full-width; B remains focused | cycle callback received |
| Stack j/k | B→A→B actual focus; both full-width | one callback per command |
| Cycle back to columns | A left/B right; B remains focused | cycle callback received |
| Normally close B | exact retained B resource confirms destruction/invalidity; A full-width and focused | B absent from candidate membership |
| Send focusNext hotkey | A remains full-width and focused | one actual callback receipt; no B membership |
| Send focusPrevious hotkey | A remains full-width and focused | one actual callback receipt; no B membership |

Each checkpoint gets a **5-second deadline**, must match for **250ms** of
observations, sampled every **50ms**, with **2 logical points** frame tolerance.
A sampling gap over **150ms** is a harness failure, not continuous stability.
Samples carry increasing IDs and guest-monotonic acquisition/delivery timestamps.
Replayed, out-of-order or older-than-150ms samples fail as harness errors; stability
uses acquisition time, not host consumption time. Both guest timestamps must be
obtained independently in the same clock domain.
The driver must return a fresh bounded native sample, never cached observations;
50ms sampling cannot be implemented as a new SSH/IPC round-trip per sample.
These are functional completion thresholds, NOT latency-budget acceptance.
Sampled stability does not prove no transient frame/focus error occurred between
samples. Timeouts retain the last observation and must not silently retry.

## Required driver boundary

Implement the `Driver` protocol in the scenario. It must:

- Verify a dedicated unlocked SIP-enabled disposable guest, single display,
  required settings/permissions, complete source/helper/fixture manifest.
- Establish an otherwise empty test Space (including pre-existing Terminal
  windows), with no previous managed members/layout history. Start exactly one
  frozen candidate in **columns**, default divider **0.5**. Current candidate
  starts in stack; use its real cycleLayout hotkey and verify receipt/state
  before starting this scenario, rather than pretending columns is configurable.
- Derive work area from native display geometry and approved bar configuration;
  never call production layout projection to obtain expected frames.
- Associate A/B with exact owned native resources. `closed` requires native
  destruction or explicit retained-resource invalidity; absence from a window
  enumeration is NOT enough. Never export unrelated window metadata.
- `frames` and `focused` come from native macOS observations, not candidate
  desired/last-applied values. For focus, read global `hs.window.focusedWindow()`
  and compare to the retained exact owned resource; verify its owning process.
  Never substitute `app:focusedWindow()`, frontmost app, title, z-order, fixture
  acknowledgement, or candidate-selected ID for actual keyboard focus.
  Require native focus **A → B → A**, alongside the correct frames at each step.
  Candidate selection/desired target/pending status are separate diagnostics;
  selection on B with actual focus on A is a failure, not a focus success.
  Fixture creation uses ordinary foreground/key-window behavior. Do not send a
  corrective focus action after creation or close. Creation proves final native
  focus, not manager causation; close recovery/navigation are independent checks.
  `managed` is a read-only candidate alias snapshot.
- `commands_received` counts actual entry to candidate hotkey callbacks using
  removable test-only instrumentation. Sender completion/event-tap receipt alone
  is not candidate command delivery. Do not invoke reducer commands directly.
- Apply deadlines to driver operations themselves; `create`, `observe`, etc.
  cannot hang beyond their runner bounds. Distinguish harness exceptions from
  behavioral `AcceptanceFailure`.
- Record action timestamps as well as every observation; include invariant IDs,
  fixed thresholds, manifests and cleanup results in structured run artifacts.
- Always stop candidate/fixture, shut down guest and verify cleanup in `finally`.
  Preserve failures for inspection. Do not load on the host or delete unknown VMs.

Native fixture eligibility and exact resource joins passed the no-manager proof.
Candidate-driver integration and hotkey receipt passed the recorded fresh-clone
sequence. Native focus/frame snapshots are independent of candidate diagnostics.
Optional regular-Space bar capture:

```sh
./functional-tests/run --headed --bar-capture --reuse-debug VM_NAME columns-close-recovery
```

After the focus/close sequence, moves the guest pointer outside → inside → outside
and captures three native screenshots. Strict fresh observations verify requested
visibility, showing, handoff, temporary pointer tracking and actual pointer position
for ≥250ms and throughout capture. `bar-evidence.json` plus images require independent
visual review; canvas state or PNG validity alone is not pixel acceptance.
The frozen `vm/capture` helper contains its exact screenshot child and may approve
only the explicitly authorized owned-guest `com.apple.sshd-session` capture prompt.
It never changes host permissions, disables SIP or writes TCC databases.

**Verified 2026-10-11:** reused debug session `8b9e9f8e636d` passed 23 native
focus checkpoints and independently reviewed custom-bar → native-menu hover →
custom-bar return pixels. All 49 frozen artifacts verified; normal cleanup.
This is not cold isolation, fullscreen/Mission Control acceptance or performance.
The earlier `78f869c3c4ad` B-readiness failure remains unresolved and preserved;
one green run does not establish general admission reliability. Two-member j/k
cannot distinguish forward from reverse ordering; rapid pending commands are untested.
The expanded scenario has not yet passed in a fresh clone.

This scenario does not certify Ghostty silent close behavior or third-party apps;
add real-app regressions separately.

## stack-columns-membership

```sh
./functional-tests/run --headed --reuse-debug VM_NAME stack-columns-membership
```

Starts empty in **stack**. Creates A/B/C; tests three-member navigation; switches
columns retaining B focus; creates D on the right; switches stack, creates E and
closes background A; returns columns and checks retained assignments plus E
integration; tests three-member column navigation; closes focused B, background E
and focused D; switches stack with sole C. All 24 actions verify independent
native frames/focus/closure and exact cached order/layout assignments. Inactive
column selections/active side are checked before reactivation can mask corruption.
Same fixed completion/sampling thresholds as the first scenario. `--demo` is
rejected because its pauses cannot fit the unchanged guest watchdog.

**Verified:** same-debug native session `d855e90e8e3e` passed 40 checkpoints;
independent reviewer verified all 51 frozen hashes and underlying observations.
The bounded readiness replacement recovered B/C/D/E from unknown ownership to
positive admission on their second creation attempt. Old B failure remains
preserved; its exact root cause is not asserted. Prior native regression
`c64997e5d01e` also passed. Details: `docs/pocs/014-bounded-readiness-layout-order.md`.
Not cold isolation, general app reliability or performance certification.

## ghostty-close-recovery

```sh
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-close-recovery
```

Requires Ghostty1.3.1 installed and prepared in the owned guest. Runner records
its executable hash/version/bundle, strict signature verification and notarization
assessment before launch. All A/B/C belong to one real Ghostty process: launch A,
Cmd+N B/C, then Ctrl+D exact C. Requires C native invalidity/removal and actual
B focus with [A]|[B] order, groups and selections intact; no navigation repair.
Owned argv disables restored windows and quit confirmation, not host settings.

**Verified guest pass:** `aa4f3c814f1a`, independently reviewed53hashes/six
checkpoints/normal cleanup. This does **not** fix or explain the reported host
silent close. Full trace includes an action-time sampling gap; matching checkpoint
windows pass, not uninterrupted sampling or performance certification. The host
observation-boundary decision remains blocked pending exact host signal evidence.
See `docs/pocs/015-ghostty-close-and-host-boundary.md` for preserved failures,
separate same-scope readiness correction and next native decision.

## Exact three-case Ghostty suite

```sh
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-close-recovery
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-column-normalization
./functional-tests/run --headed --reuse-debug VM_NAME ghostty-layout-retention
```

Normalization starts in stack: createABC → kB/kA → columnsAB|C → lC →
CtrlD C → A|B/nativeB. Retention starts columnsA|BC, switches to stack,
navigates three members, returns columns and repeats; physical groups/order never
change. No swap/move/reflow or post-close repair. All are same-process Ghostty,
with fixed native geometry/focus and separate exact cached-order assertions.
Independent review confirms all three native runs (56 frozen hashes each), normal
cleanup and unchanged checkpoint gates. They do not establish a host fix.

Host silent-close recovery remains blocked: no alternate closeevent observed and
synchronous focused AX safety-query POC failed fixed tail-cost/gap gates. No polling
workaround added. Evidence/next architectural hypothesis:
`docs/pocs/016-three-ghostty-cases-safety-cost.md`.

## Scenario self-checks

```sh
python3 -m unittest discover -s functional-tests -p 'test_*.py' -v
```

Checks include the intended sequence, an intentionally wrong native frame,
wrong actual focus despite correct candidate state, retained dead membership,
and undelivered hotkeys. These prove the oracle detects modeled mismatches—not
that the implementation satisfies acceptance.
