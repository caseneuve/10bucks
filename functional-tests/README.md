# Native functional acceptance scenarios

First executable scenario: `scenarios/columns_close_recovery.py`.
**Not yet runnable against the VM:** the native fixture and guest/host driver
are not implemented. Self-checks below test scenario logic only, not macOS or
10bucks behavior. Production Lua is unchanged.

## columns-close-recovery

Contracts: COL-002, COL-005, WIN-005, FOCUS-004, FOCUS-006.

| Step | Native assertion | Secondary assertion |
| --- | --- | --- |
| Create A | A fills independently computed usable area; A focused | managed aliases = A |
| Create B | A left half, B right half; B focused | managed aliases = A,B |
| Normally close B | exact retained B resource confirms destruction/invalidity; A full-width and focused | B absent from candidate membership |
| Send focusNext hotkey | A remains full-width and focused | one actual callback receipt; no B membership |
| Send focusPrevious hotkey | A remains full-width and focused | one actual callback receipt; no B membership |

Each checkpoint gets a **5-second deadline**, must match for **250ms** of
observations, sampled every **50ms**, with **2 logical points** frame tolerance.
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
  desired/last-applied values. `managed` is a read-only candidate alias snapshot.
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

Native fixture eligibility, reliable alias/resource join, and callback receipt
instrumentation still need proof. This scenario does not certify Ghostty silent
close behavior or third-party apps; add real-app regressions separately.

## Scenario self-checks

```sh
python3 -m unittest discover -s functional-tests -p 'test_*.py' -v
```

Checks include the intended sequence, an intentionally wrong native frame,
wrong actual focus despite correct candidate state, retained dead membership,
and undelivered hotkeys. These prove the oracle detects modeled mismatches—not
that the implementation satisfies acceptance.
