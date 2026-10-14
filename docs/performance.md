# Performance Contract

> **Status: target release gates.** Performance claims require measurements on the supported Mac. The broader application matrix is hardening/release coverage; local acceptance uses a workload relevant to the changed path, not broad platform certification.

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

Measure when the patch changes a performance-sensitive native call/query path,
adds recurring work, addresses a performance defect, or makes a latency/resource
claim. A local pure selection-policy correction using unchanged native effects does
not automatically require fresh cold populations, an independent sender or a full
benchmark. Explain the applicable risk and reuse comparable recorded evidence;
record a focused timing check if that is sufficient for the patch. Release budgets
remain unchanged, and a claim that a budget passes requires adequate measurements.

For a statistical benchmark or budget-certification claim:

- record OS build, Hammerspoon version, 10bucks commit, display setup, and relevant settings
- use at least 30 warm samples and 5 cold samples when a cold path exists; justify a smaller destructive-operation sample explicitly
- test cold and warm paths when meaningful
- run enough samples to report count, median, p95, and maximum
- count global AX calls, private Space queries, frame writes, renders, and timers
- preserve timestamped normalized event/effect traces
- use a representative workload for the affected path; the broader slow-application matrix belongs to release/hardening, not every local patch
- timestamp physical/test key receipt, callback arrival, effect request, native confirmation, and next-key service separately
- when the changed path can block AX/Space service, measure input arriving while that work is pending; post-operation synthetic callbacks are not concurrent-service proof
- distinguish callback arrival latency from 10bucks processing latency
- fix operation-specific timeout and eventual-detection thresholds in the POC before running it
- record failures/timeouts and late completions, not only successful samples

Representative applications for applicable hardening/release dogfood:

- Terminal
- Chromium-based browser/app
- Slack
- Signal
- Thunderbird
- Claude
- Zoom

Chromium and the rest of this list do not select production adapter policy. A finding may justify a generic, measured adapter correction; app-specific production behavior remains forbidden.

## Baseline evidence from the legacy runtime

These historical measurements motivate the plan; they are not a recurring
reproduction obligation. Measure the relevant current path when a risk/claim
requires it, and do not infer current performance from these legacy samples:

- Repeated `hs.window.get(id)` in reflow was observed around 1.5 seconds per lookup with slow Accessibility applications; one reflow reached roughly 11 seconds.
- Reusing one eligible-window snapshot reduced ordinary reflow to roughly 2–80 ms, but the legacy implementation then incorrectly used snapshot absence as proof of death.
- A current-machine `hs` CLI no-op benchmark (`n=25`) measured about 21 ms median, 39 ms p95, and a 310 ms maximum. This is why CLI/skhd dispatch is deferred from MVP.
- Spot—not statistically sufficient—private Space reads on the current machine were around 4.6–7.1 ms. They are reasonable when event-driven and a tax when polled/repeated.

## Hammerspoon viability and escalation

Start the pure core and direct-AX adapter without broad platform certification. Evaluate Hammerspoon through measurements of the affected composed paths when
performance risk or a delivery/release claim requires them:

- event callbacks normalize without destructive global refreshes;
- hotkey, layout, chooser, and bar budgets pass where those slices exist;
- manual Space moves and destruction use explicit facts or a proven non-destructive targeted check; and
- the overlay bar is reliable when the bar slice is undertaken.

If a completed slice exposes an intrinsic boundary failure, POC the smallest native Swift/Objective-C adapter for that boundary. A native rewrite is not justified by legacy architecture or Lua line count alone.

## Release evidence

Record measured performance results and qualifications when the changed path or
claim calls for them; use an existing result/TODO when it suffices, not a mandatory
new POC document per patch. A release cannot claim a performance issue fixed solely
because unit tests pass or one fast run was observed. Do not repeat unchanged
benchmarks to satisfy a procedural quota.
