# Performance Contract

> **Status: target release gates.** Performance claims require measurements on the supported Mac. The representative application matrix is ordinary slice acceptance and release dogfood, not broad pre-implementation platform certification.

10bucks runs inside Hammerspoon's single Lua/main-thread environment. A blocking Accessibility or private Spaces call delays hotkeys, bar updates, timers, and every other callback. The design therefore optimizes query count and placement of work before micro-optimizing Lua.

## MVP budgets

| Operation | Gate |
|---|---:|
| Physical layout/focus hotkey to effect request | p95 ≤ 50 ms |
| A second hotkey serviced while AX/Space work is pending | p95 ≤ 50 ms; maximum ≤ 100 ms |
| Same-Space managed focus completion | p95 ≤ 100 ms |
| Chooser invocation to visible | p95 ≤ 100 ms |
| `WindowReady` callback to final requested frame | p95 ≤ 100 ms |
| Bar render after an already-received state event | ≤ 100 ms |
| Frame writes per affected window/transaction | ≤ 1 |
| Idle layout/window/Space queries | 0 |
| Clock timer | one minute-boundary timer |
| Global AX enumeration | startup bootstrap or explicit POC-approved recovery only |

Native Space/fullscreen animation time is recorded separately from 10bucks command overhead. Creation/deletion may be visibly slower because Mission Control Accessibility automation is accepted for infrequent operations, but visual animation MUST NOT excuse a blocked Hammerspoon main thread that cannot service another keypress.

No created window may receive a temporary wrong-stack/wrong-column 10bucks frame before its final frame.

## Query/effect budgets

- One event transaction may obtain one necessary relevant observation snapshot.
- Build one `windowId -> handle` map from a snapshot; reuse it for projection/effects.
- Never call `hs.window.get(id)` or enumerate all applications from a managed-window loop.
- Never query full Space topology repeatedly while formatting one bar update.
- Cache normalized window metadata and app icons on events, not chooser invocation.
- Compare intended and observed/last-applied frames before calling `setFrame`.
- Do not render/reorder/show a bar canvas when its semantic view model did not change.
- Bounded retries must stop on success, replacement by a newer generation, timeout, or shutdown.

## Allowed timer classes

1. Clock timer aligned to the next minute boundary, then once per minute.
2. Bounded one-shot retries/timeouts for a specific focus/fullscreen/Space operation.
3. Temporary pointer tracking while the custom bar is hidden for native menu-bar handoff.
4. A safety poll only if a recorded POC proves an otherwise silent correctness gap and measures a cheap, non-destructive targeted check.

The legacy 150 ms bar refresh and 250 ms destructive reconciliation timer are not accepted.

## Measurement method

Sample the applicable gates and counters during every scheduled implementation canary, rather than deferring all measurement to final dogfood or release. Canary measurements validate the active development composition; they are not a new POC or broad certification program.

For each benchmark:

- record OS build, Hammerspoon version, 10bucks commit, display setup, and relevant settings
- use at least 30 warm samples and 5 cold samples when a cold path exists; justify a smaller destructive-operation sample explicitly
- test cold and warm paths when meaningful
- run enough samples to report count, median, p95, and maximum
- count global AX calls, private Space queries, frame writes, renders, and timers
- preserve timestamped normalized event/effect traces
- run while representative slow Accessibility apps are open
- timestamp physical/test key receipt, callback arrival, effect request, native confirmation, and next-key service separately
- while long AX/Space work is pending, send a benign instrumented hotkey to measure main-thread service stalls
- distinguish callback arrival latency from 10bucks processing latency
- fix operation-specific timeout and eventual-detection thresholds in the POC before running it
- record failures/timeouts and late completions, not only successful samples

Representative applications for slice acceptance and release dogfood:

- Terminal
- Chromium-based browser/app
- Slack
- Signal
- Thunderbird
- Claude
- Zoom

Chromium and the rest of this list do not select production adapter policy. A finding may justify a generic, measured adapter correction; app-specific production behavior remains forbidden.

## Baseline evidence from the legacy runtime

These measurements motivate the plan; POCs must reproduce/replace them with committed evidence:

- Repeated `hs.window.get(id)` in reflow was observed around 1.5 seconds per lookup with slow Accessibility applications; one reflow reached roughly 11 seconds.
- Reusing one eligible-window snapshot reduced ordinary reflow to roughly 2–80 ms, but the legacy implementation then incorrectly used snapshot absence as proof of death.
- A current-machine `hs` CLI no-op benchmark (`n=25`) measured about 21 ms median, 39 ms p95, and a 310 ms maximum. This is why CLI/skhd dispatch is deferred from MVP.
- Spot—not statistically sufficient—private Space reads on the current machine were around 4.6–7.1 ms. They are reasonable when event-driven and a tax when polled/repeated.

## Hammerspoon viability and escalation

Start the pure core and direct-AX adapter without broad platform certification. Evaluate Hammerspoon through the measurements attached to each composed slice:

- event callbacks normalize without destructive global refreshes;
- hotkey, layout, chooser, and bar budgets pass where those slices exist;
- manual Space moves and destruction use explicit facts or a proven non-destructive targeted check; and
- the overlay bar is reliable when the bar slice is undertaken.

If a completed slice exposes an intrinsic boundary failure, POC the smallest native Swift/Objective-C adapter for that boundary. A native rewrite is not justified by legacy architecture or Lua line count alone.

## Release evidence

Every rewritten milestone records its benchmark result under `docs/pocs/`. A release cannot claim a performance issue fixed solely because unit tests pass or because one fast run was observed.
