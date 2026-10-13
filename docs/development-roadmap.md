# Remaining feature delivery order

Approved by the user on 2026-10-11. This is the current scheduling decision,
not a claim that the running rewrite implements every target contract.
`invariants.md` defines behavior; `architecture.md` defines boundaries;
`rewrite-plan.md` retains the replacement and evidence discipline.

## Order

| Step | Deliverable | Native acceptance focus |
|---|---|---|
| 1 | **Desktop switching**: existing numbered regular desktops, cyclic previous/next, previous-confirmed-desktop toggle | Real shortcut receipts; native destination confirmation; pending-command coalescing; retained layouts/order on return; key-service budgets |
| 2 | **Desktop creation**: one next contiguous native regular desktop, then focus it | Actual topology change/confirmation; no gaps or duplicate mutations; keyboard responsiveness during the operation |
| 3 | **Configured rules, including exemptions**: ordered first-match `manage`/`exclude` | Excluded windows receive no manager frame/focus effects or membership; managed history/chooser scope; commands remain usable with excluded actual focus |
| 4 | **Cached managed-window chooser** | No enumeration on invocation; stable rows; correct titles and selected native target; chooser latency |
| 5 | **Restoration behavior** through chooser/previous-window | Unminimize/unhide or enter target native-fullscreen Space, then confirm focus; independent lifecycle flags; preserved slots/order |
| 6 | **Native fullscreen commands and creation effects** | Toggle serialization/confirmation; `nativeFullscreenOnCreate`; retained manual-fullscreen placement; no temporary tiled frame on spawn-fullscreen |
| 7 | **Hardening and release performance acceptance** | Combined lifecycle/layout/Space sequences, rapid input, real-app dogfood, bar transitions, supported-host latency/query/resource budgets |

**Deferred by explicit user decision:** keyboard move-to-desktop without following
(former step 3), and desktop deletion. Do not implement either opportunistically
inside switching/creation. Their `SPACE-010` and `SPACE-007/008` contracts remain
specified for future work, not silently removed or weakened. Reactivation requires
a deliberate user decision and the applicable native evidence.

Other established deferrals remain: multiple displays, managed floating windows,
CLI/skhd control, reload/cross-reboot layout persistence, dedicated regular desktop
after spawn-fullscreen exit, arbitrary plugins and version-compatibility shims.

## Meaning of rules and restoration

An exemption uses `exclude`: outside tiling/layout membership, managed navigation,
managed chooser and managed focus history. Native focus and actual-title bar
presentation remain allowed. Match app identity/title/normalized window metadata
in user config, not external-app branches in production. Evaluate once at confirmed
admission; later title changes do not automatically reclassify the member. Verify
actual Thunderbird sending-dialog metadata before choosing a stable user rule.
The action name `nativeFullscreenOnCreate` remains specified, but its native effect
is delivered in step 6, not implied by step 3's manage/exclude delivery.

Restoration means bringing an existing managed window into use: unminimize a
window, unhide its app, or focus its native-fullscreen Space. Preserve regular
layout membership/slot/order when the native destination remains the original
Space. Unhiding must not clear minimize/fullscreen. It does **not** mean restoring
layouts after Hammerspoon restart or reboot. Step 5 can reuse independently proved
fullscreen focus mechanisms; step 6 adds explicit toggle/spawn effects.

## Gate for every step—not only the last one

1. Cite existing platform evidence; verify official installed API contracts first.
2. Reproduce the target invariant/sequence in tests. Pure checks are not native proof.
3. Direct replacement through the single runtime; no shadow/compatibility path.
4. Freeze source, helpers and executed binaries; run bounded native functional
   tests with independent outcomes and real callback receipts.
5. Independently review underlying traces, failures and cleanup—not only verdicts.
6. Measure the relevant performance/query/resource gates before calling the step done.
7. Delete replaced production code and obsolete tests in that slice; commit the
   reviewed green checkpoint, preserve failures, update the operational handoff.

Step 7 closes residual release coverage; it does not postpone the earlier gates.
Performance budgets in `performance.md` are unchanged. Native animation time is
separate from command service, and sender completion never proves hotkey receipt.

## Delivered checkpoint and next action

**Desktop switching accepted by the user on 2026-10-12**, runtime `66cdc06`:
numbered existing regular desktops, cyclic positional N/P, and previous-history0
including the regular desktop departed into fullscreen. Native VM scenarios and
manual host feedback are recorded in
[`pocs/018-existing-desktop-switching.md`](pocs/018-existing-desktop-switching.md).
Its explicit evidence/performance qualifications remain; user acceptance does not
retroactively repair POC002 failures or certify full release performance.

**Desktop creation accepted by the user on 2026-10-13**, runtime `f384ec7`:
a separate configurable HyperD default appends one regular desktop at the end of
current native regular-Space order and focuses it; digits remain focus-only.
The user explicitly retained this design rather than choosing a creation number. Regular/fullscreen-source/external-race
scenarios, pending focus/layout service, 30 warm/5 cold measurements and independent
sender evidence are recorded in [`pocs/019-desktop-creation.md`](pocs/019-desktop-creation.md).
User host acceptance does not certify full release performance or erase recorded
failures/qualifications. The accepted creation candidate remains active and frozen;
HyperC belongs to the user's skhd Chrome mode, which was left unchanged.

Next implementation scope is **configured rules, including exemptions**: ordered
first-match `manage`/`exclude` over normalized metadata, evaluated at confirmed
readiness with stable lifetime decisions. Excluded windows receive no manager
frames/focus or managed membership/navigation/history/chooser entries; actual focus
and title presentation remain observable. Commands remain usable from excluded
actual focus. Keep policy in user configuration, not external-app source branches.
`nativeFullscreenOnCreate` native effects remain step 6; chooser UI is step 4.
Movement and deletion remain deferred.

The accepted host runtime stays frozen and active until a deliberate source/runtime
handoff before production edits or native builds; see WORK_STATE for exact ownership
and rollback. Do not use unchanged synchronous `hs.spaces.gotoSpace()` in hotkeys.

Fresh-session operational entry: read `.pi/WORK_STATE.md`, then
`.pi/handoffs/2026-10-13-configured-rules-next.md`. The ignored handoff holds exact
live host/VM ownership, rollback and worker protocol; this tracked roadmap holds
the durable user-approved order. Neither authorizes host window/Space mutations
merely by being read.
