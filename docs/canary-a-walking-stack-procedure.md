# Canary A walking-stack behavioral procedure

## Status

**Target agile qualitative walking-skeleton smoke.** It is not a PERF gate and cannot establish p95 latency claims. It is not authorization to switch the installed Spoon. The lead must state expected duration/disruption and obtain fresh explicit approval before `start-capture`.

## Scope and safety

- Original active regular Space only.
- Disposable Terminal windows only; do not close any non-disposable window.
- No autonomous runner window action exists.
- Expected disruption: stable 10bucks is stopped while Canary A is active; `finish` restores stable in the same command.
- The live config, temporary config, backup, and approval are owner-owned regular non-symlink files. Each is owner-private (no group/other bits); approval is exactly mode `0600`, and contains exactly `{"candidateCommit":"<full HEAD>"}`. Config replacement is atomic and never follows a symlink.

## Preflight

1. Commit/review the candidate; the runner rejects a dirty candidate tree.
2. Write the temporary Canary config with private display UUID and:
   ```lua
   return { builtInDisplayUUID = "<private>", canaryInstrumentation = true }
   ```
3. Run:
   ```sh
   python3 scripts/canary-walking-stack.py preflight
   ```
   This read-only check queries the actual focused `hs.window`, its AX element, and application before fakes are relevant. It requires exactly `window.newWatcher=function`, `AX element.newWatcher=nil`, and `application.newWatcher=function`. It also rejects config symlinks/non-regular files. Record only returned aggregate/baseline data privately. Abort if the watcher shape, version, baseline, or stable link/commit is unavailable.
4. After explicit approval only:
   ```sh
   python3 scripts/canary-walking-stack.py start-capture --execute \
     --approval OWNER_PRIVATE_APPROVAL --temporary-config OWNER_PRIVATE_CONFIG
   ```
   The command first stops and verifies stable (zero bindings/lifecycle/reconcile/bar/canvas owners), then swaps. It automatically attempts rollback on any post-stop failure.
5. Require candidate status: `started=true`, `bindings=11`, `canary.enabled=true`, `canary.activeTimers=0`, and `suspended=false`. Abort and run `finish` if any differs.

## Human-led actions and checks

Run `status` immediately before/after each human action:

```sh
python3 scripts/canary-walking-stack.py status
```

Status contains no IDs/titles: runtime `started`, `suspended`, `memberCount`, committed reducer `version`, active timers, and aggregate event/effect/query counters. The candidate does not poll. If a bounded external check is useful, the runner may poll status every 100 ms only for one named aggregate counter delta:

```sh
python3 scripts/canary-walking-stack.py wait-status --counter event.WindowReady --delta 1 --deadline-ms 2000
```

This is runner-side bounded observation, not candidate polling. Compare only aggregate deltas; frame requests are projection-wide and cannot prove per-transaction frame attribution.

1. **Bootstrap.** Do not create anything. Confirm `memberCount` matches only the disposable Terminal windows already on the original Space; `event.WindowReady`, `reducerCommitVersions`, `frameRequests`, and `frameWrites` may increase. Require `frameWrites <= frameRequests` and `activeTimers=0`.
2. **Create.** Human creates one disposable Terminal window. Candidate startup must have completed within **10 s** of the approved start request. Within **2 s** of each human create/destroy action, use a human-triggered `status` (or the bounded external `wait-status`) to confirm the visible status delta: `event.WindowReady`/member count +1 for create; `event.WindowDestroyed`/member count -1 for destroy. Require committed `version` to advance and inspect aggregate frame-write delta with the visible result. No wrong temporary frame is acceptable.
3. **Navigation.** Human presses configured `j`, then `k`. Immediately after each action, status must show a focus-request aggregate delta of **at most one** within **1 s**. Membership and frame-write aggregates must not increase merely from navigation.
4. **Foreground close.** Human focuses and closes a disposable Terminal window. Apply the preceding **2 s** status deadline. The remaining stack may issue one recovery focus request; no global scan/poll is permitted.
5. **Background close.** Human creates another disposable Terminal window, focuses a different disposable Terminal window, then closes the background one. Apply the same create/destroy deadlines and require no unexpected focus request.

## Abort criteria

Abort immediately for candidate startup exceeding 10 s or mismatch, any nonzero active timer, suspension, an unexpected member-count change, a missing create/destroy status delta by its 2 s deadline, a navigation focus-request delta above one or not observed within 1 s, any system responsiveness concern, or any interaction with a non-disposable window. Do not diagnose by candidate polling or run a second live action. Instrumentation supports smoke counters only: report aggregate deltas and flag any ambiguous attribution; do not claim a per-transaction frame abort from these aggregates. The 30 warm / 5 cold performance sampling remains **Deferred** until the walking skeleton works, and must occur before this slice is accepted as performance-complete.

## Finish and restoration

Always finish—also after abort—using the atomic export/restore command:

```sh
python3 scripts/canary-walking-stack.py finish --execute --approval OWNER_PRIVATE_APPROVAL
```

`finish` exports counters, stops candidate, restores the exact config bytes/mode and original symlink/commit, reloads with expected IPC invalidation handling, explicitly starts and rebinds stable, then compares its complete captured baseline: version, started flag, bindings, lifecycle watcher, reconciliation timer, bar timer, and canvas count. A mismatch is a failed restoration, never a successful result.
