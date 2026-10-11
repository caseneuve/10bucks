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

## Baseline and next action

As of runtime commit `cfc6c59`, the composed rewrite has layout/focus/divider/reflow
bindings and the bar, not desktop-switch bindings or a chooser/rules interface.
`10bucks.spoon/lib/workspace_switch.lua` is a pure, tested **uncomposed** seam—not a native adapter
or accepted switching implementation. POC-002 observed a narrow asynchronous
switch-and-return mechanism but failed key-service budgets; no performance pass,
reorder-notification proof or native-numbered-shortcut equivalence is implied.

Next implementation scope is **existing desktop switching only**. Review the pure
workspace reducer and current persistent Host/context composition, reuse POC-002
mechanism evidence where it actually applies, and first specify switching/return,
pending-input and responsiveness acceptance. Do not reuse synchronous
`hs.spaces.gotoSpace()` unchanged: its observed busy-wait behavior is rejected for
the hotkey path. Native numbered shortcuts remain a hypothesis until proved to
match filtered positional regular-desktop numbering.

Fresh-session operational entry: read `.pi/WORK_STATE.md`, then
`.pi/handoffs/2026-10-11-desktop-switching-next.md`. The ignored handoff holds exact
live host/VM ownership, rollback and worker protocol; this tracked roadmap holds
the durable user-approved order. Neither authorizes host window/Space mutations
merely by being read.
