# POC-001 — proposed AppKit timing fixture (separately gated)

**Status: proposal only.** Chromium sample 006 is complete and its narrow,
redacted aggregates are now in the canonical
[`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md).
POC-001 remains `hypothesis`. **This documentation checkpoint authorizes no
fixture implementation, build, launch, Hammerspoon reload, observer load, or
live action.** A later explicit handoff must approve the implementation and
live procedure separately.

## Decision the proposal would inform

The current Chromium result has paired destruction candidates but no controlled
native close-completion marker and no pending-work service measurement. This
proposal would provide a small, controlled timestamp source for *a fixture's
own* native AppKit create/close lifecycle, plus a probe that establishes when
its queued pending work is serviced. It would only make a later timing
experiment possible; it does not select an event source, destruction authority,
production adapter, or native replacement.

## Frozen scope

If separately approved, create one standalone, disposable macOS AppKit fixture
under `pocs/001-window-events-liveness/fixture/` (or an equally POC-local path
named in that approval). Its entire scope is:

1. create a uniquely labelled temporary native fixture window on explicit
   operator request;
2. close that fixture window on explicit operator request;
3. emit monotonic timestamps for the fixture's request, native create
   completion, close request, and native close completion; and
4. accept one explicit pending-work probe and emit its request and service
   timestamps.

The fixture may use public AppKit/Foundation APIs only unless a later approval
names and justifies a narrower exception. Timestamps must use one documented
monotonic native clock, with its units and conversion recorded in the trace.
"Completion" must name the exact AppKit callback/hook observed; it must not be
substituted with a visual guess, a sleep, window ordering, or an Accessibility
snapshot.

The fixture must expose a machine-readable, privacy-safe trace with a run ID,
sample ID, event name, sequence, monotonic timestamp, and a fixture-local
window token. It may also print a concise operator status line. The pending-work
probe must identify the explicit queue/run-loop mechanism and record both its
request and actual service point. It must not claim to measure Hammerspoon
hotkey service unless a separately approved integration delivers and records
that exact boundary.

## Explicit exclusions and isolation

This is not production code and must never be loaded, packaged, installed, or
called by `10bucks.spoon`, its configuration, tests, release artifact, or
runtime startup path. It must not be a shadow/compatibility implementation of
window observation, liveness, destruction, Space ownership, focus, layout, or
any production effect.

The fixture must not:

- observe, enumerate, attach to, move, focus, minimize, hide, fullscreen,
  resize, close, or otherwise affect a non-fixture window;
- use `hs`, Accessibility APIs, private Spaces APIs, polling, a privileged
  helper, root access, disabled SIP, login items, background agents, or
  persistent services;
- modify Hammerspoon configuration or reload Hammerspoon;
- make a Chromium, Terminal, or representative-app claim; or
- add a production dependency, feature flag, fallback, or second runtime path.

A later integration experiment with the POC observer, if needed, is a distinct
gate and must retain these restrictions unless its approval explicitly changes
them. The fixture's own timestamps cannot validate callback delivery or
liveness for another application.

## Separately gated implementation handoff

Before any code is written, an approver must freeze all of the following in a
new handoff (not by editing this proposal during a run):

- fixture language/toolchain, supported macOS build, signing/quarantine
  handling, and the exact public completion hooks;
- the exact command/operator sequence, sample IDs, warm/cold definitions, and
  stop conditions;
- trace schema, monotonic-clock conversion, output directory, and the precise
  pending-work queue/run-loop mechanism;
- whether and how a later POC-only observer correlation receives fixture
  tokens, without exposing raw native IDs; and
- fixed acceptance thresholds and the planned result-document location.

No live run may start until that handoff also names an operator, confirms that
legacy 10bucks is not being exercised concurrently if Hammerspoon is involved,
and confirms a clean fixture build/output location. The current README is not
that handoff.

## Proposed acceptance measurements

These are measurement requirements for the future approval, not pass criteria
claimed now. That approval must set numeric thresholds before collecting data.
For each declared warm/cold create and close class, it must retain count,
median, nearest-rank p95, maximum, timeout count, and late completion count for:

- fixture create request → named native create completion;
- fixture close request → named native close completion; and
- pending-work probe request → named service point.

It must also record callback/event ordering, duplicate/missing completion
signals, fixture process exit, active timers/polls (expected zero unless the
future approval explicitly permits a bounded timeout), and cleanup outcome.
At least 30 warm samples and 5 cold samples are proposed for each meaningful
non-destructive class; any smaller destructive sample count must be justified
and cannot support a broad percentile claim. A failed, timed-out, or late
sample remains in the aggregate. These measurements establish only the stated
fixture behavior and service point.

## Privacy, cleanup, and failure handling

Use a generic fixture-local token; never commit raw window IDs, titles, document
paths, URLs, account names, screenshots, AX dumps, or unrelated application
information. Keep raw traces in an owner-private directory (`0700`) and output
files owner-readable only (`0600`); commit only redacted aggregates after local
review. A trace-export failure, unsafe permissions, unexpected non-fixture
window interaction, or inability to identify the completion hook fails closed:
stop the fixture, preserve/redact local diagnostics as permitted, and mark the
sample unresolved rather than retrying ad hoc.

Every run must explicitly close every fixture window, stop any bounded timeout
or probe work, terminate the fixture, and verify that no fixture process,
service, login item, agent, watcher, or output remains outside the approved
private directory. Delete the fixture source, build products, and local traces
when the POC is concluded unless a later result document names a continuing
POC-only diagnostic owner, use, and negligible idle cost. No artifact is
reusable by production merely because it exists.

## Current action

**None.** Do not implement the fixture or perform a live action from this
README. The only authorized work in this checkpoint is documenting this proposal
and the completed Chromium sample 006 result.
