# Target Invariants

> **Status: normative target contracts, not a description of the current runtime.** Tests for rewritten behavior should reference these IDs. Revise an invariant deliberately before changing its meaning.

Keywords **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are normative.

## Platform and scope

### ENV-001 — Supported MVP environment

MVP supports macOS 26.x on Apple Silicon, Hammerspoon 1.1.1, SIP enabled, and the built-in display. Other versions and multiple displays are unverified; compatibility code is not required.

### ENV-002 — Security/dependency boundary

10bucks MUST NOT require disabled SIP, root access, a privileged helper, AeroSpace, or yabai.

### ENV-003 — Required macOS settings

The required settings in [`macos-settings.md`](macos-settings.md) are user responsibility. MVP documents them; runtime MUST NOT silently mutate them.

### ENV-004 — Explicit display identity

Although MVP accepts only the built-in display, core state, Space records, layout context, work areas, and bar adapter ownership MUST carry explicit display identity. Core/layout code MUST NOT depend on a global “main screen.” Multi-display behavior itself remains deferred.

## State and transactions

### STATE-001 — Single writer

Only the reducer may change durable manager state. Queries, layout projection/reflow, renderers, adapters, timers, and effect execution MUST NOT mutate it.

### STATE-002 — Atomic decision before effect

A complete next state MUST commit before any frame, focus, native fullscreen, or Space effect is requested.

### STATE-003 — Primitive durable state

Durable state MUST contain plain Lua values. Hammerspoon userdata—including windows, AX elements, canvases, watchers, choosers, and timers—MUST remain in adapters.

### STATE-004 — Observation is not liveness

Absence from `_orderedwinids()`, visible/eligible/onscreen windows, the active Space, or one observation snapshot MUST NOT remove durable membership.

### STATE-005 — Uncertainty is non-destructive

When window liveness is uncertain, 10bucks MUST retain the member rather than corrupt a potentially live layout. Permanent removal requires an authoritative event or POC-validated targeted check. AX invalidity while the session is locked/off-console is not destruction evidence: exact window handles may revive after unlock. Delayed worker invalidity MUST be reconfirmed on the retained exact resource in the current usable session before removal (POC-027).

### STATE-006 — Projection purity

Layout projection/reflow MUST compute frame intents from committed layout state and current availability. It MUST NOT admit, remove, reorder, select, or reassign a window.

### STATE-007 — One runtime path

Production MUST have one active implementation of each behavior. Compatibility, shadow, and indefinite feature-flag paths are forbidden.

### STATE-008 — Derived availability

Minimized, app-hidden, and native-fullscreen are independent lifecycle conditions and MAY overlap. Availability for tiling/navigation is derived from all conditions; clearing one condition MUST NOT make a window available while another remains set.

## Management and ordering

### WIN-001 — Managed versus excluded

An excluded window is outside layout membership, chooser results, and managed focus history. It MAY still be the actual macOS focused window shown by the bar.

### WIN-002 — Stable order

Focus, z-order, Space activation, snapshots, reflow, and title changes MUST NOT reorder a stack. Availability changes preserve survivor order except for the visible-column normalization required by COL-004.

### WIN-003 — Admission order

A newly created or post-start discovered window appends according to the active layout's admission policy and receives managed selection/focus intent. Cold-bootstrap discovery appends without requesting focus merely because it was discovered; actual managed focus determines bootstrap selection as specified by COL-009. Only explicit structural commands and COL-004/COL-005 visible-column normalization may otherwise change layout order/grouping.

### WIN-004 — Temporary unavailability

Minimizing a window, hiding its application, or manually native-fullscreening an admitted window MUST retain its managed membership. Unavailable members retain their assignments; available survivors may change columns under COL-004. Restore MUST NOT undo that normalization.

### WIN-005 — Destruction

Confirmed destruction permanently removes the window from membership, all layout states, chooser state, and managed focus history.

### WIN-006 — Manual cross-Space movement

A managed window manually moved to another regular Space MUST be removed from its source and newly admitted to its actual destination. Source column/slot MUST NOT follow it.

### WIN-007 — Same-Space manual frame drift

Dragging/resizing a tiled window on the same Space MUST NOT trigger immediate resistance. Its canonical frame is reapplied at the next layout synchronization boundary: managed focus change, 10bucks layout/focus command, create/destroy/restore, Space activation, or explicit reflow.

### WIN-008 — No app-specific source policy

Production behavior MUST NOT branch on Slack, Signal, Thunderbird, Claude, Zoom, Chromium, or another external app identity. App-specific policy belongs in user rules; app-specific quirks require recorded evidence and an isolated generic adapter fix.

## Layout framework

### LAY-001 — Per-Space active layout

Every regular Space owns its active layout and layout-owned state independently. Layout choice, ratio, grouping, selection, and order are not global.

### LAY-002 — Relative layout cycling

`cycleLayout` MUST find the current layout in the configured unique ordered list, select the next entry, and wrap. It MUST NOT select the current/first layout as a naive first step.

### LAY-003 — Inactive layout retention and focus continuity

Switching away from a layout MUST retain its state. Switching back restores surviving assignments/order. Windows admitted while it was inactive are synchronized deterministically on activation. A layout switch MUST NOT change actual managed focus: the destination layout activates the group containing the currently focused managed window and selects that same window. If actual focus is unmanaged, it uses the last managed focus for that Space. Other groups retain their own selections unchanged.

### LAY-004 — Extensible layout boundary

Core/runtime code MUST NOT branch on `layout.id` to implement columns behavior. A new layout implements the approved layout reducer/projector/status/validation interface and registers through configuration/composition.

### STACK-001 — Stack geometry

Stack layout has one stable stack. Every currently available member receives the same usable display frame inset on all sides by the configured `columnGap` (default 0). The effective gap is clamped to `min(columnGap, usableWidth / 2, usableHeight / 2)`, with nonnegative dimensions. This shared gap also applies in columns mode; it never changes membership or selection. Decorations, native menu-bar area, and 10bucks bar remain normally visible.

### STACK-002 — Stack navigation

`j`/`k` cycles available members in stable order with wraparound. Minimized, hidden, and native-fullscreen members are skipped without changing durable order.

### COL-001 — Column structure

Columns means visible columns: at most two stacks with available members. Retained unavailable members are managed windows, not hidden columns, and MUST NOT count as an occupied column for admission or prevent normalization. Durable assignment stacks MUST remain non-empty.

### COL-002 — First split

When only one visible column exists, the next newly admitted available window MUST normalize the existing visible stack to the physical left and create/focus a right stack. This applies even when the existing stack contains more than one member.

### COL-003 — Normal admission

When both visible columns exist, a new window appends to the currently active column and receives selection/focus intent.

### COL-004 — Availability-driven column loss

When minimizing, app hiding, or native fullscreen leaves a column with no available members, apply the same visible-survivor normalization as COL-005: with at least two available survivors, keep all but the newest available survivor on the physical left and move the newest to the right, preserving survivor order. With one available survivor, project one full-width column; the next available admission follows COL-002. With none, project no columns. Unavailable windows remain managed with their retained assignments and lifecycle flags; they do not reserve a hidden column. Restore uses the resulting assignments and MUST NOT move normalized survivors back. Focused minimize recovery stays on the physical source side when normalization supplies a replacement; background availability changes MUST NOT request focus. This user-approved correction (2026-11-01) replaces exact-slot restoration of available survivors.

### COL-005 — Permanent empty column

Destroying or cross-Space-moving the last durable member removes that column. If at least two available windows survive in the other column, columns immediately normalizes them back to two visible physical columns by retaining their order, keeping all but the newest available member on the left, and moving the newest available member to the right. With only one available survivor, one visible column remains and the next admission follows COL-002. If the destroyed window had managed focus, recovery remains on its physical source column when that column has or receives a replacement; it selects the most recently confirmed focused available survivor in that column, falling back to the last available member in stable order when no survivor has focus history. It MUST NOT jump to the other column merely because macOS reported a transient fallback focus first.

### COL-006 — Move between columns

Moving the actually focused managed window to the other column focuses/selects it there. If its source has more than one durable member, the move appends it to the destination and preserves source survivor order. If it is the sole source member, the move atomically refills its source with the last available destination member in stable order other than the destination's retained selected member, then prepends the moved member to the destination while preserving all other destination order. The replacement becomes selected in the source. Minimized, app-hidden and native-fullscreen members are ineligible replacements according to independent availability conditions; they retain their slots. If no replacement exists (including only two total members), or there are not two columns, the operation MUST be rejected unchanged. Neither an empty durable column nor an intermediate empty-column frame intent may be produced.

### COL-007 — Swap columns

Swapping columns atomically swaps whole ordered stacks and their selections. The focused/active stack follows its content to the other physical side. `h`/`FocusLeftGroup` targets the physical left column and `l`/`FocusRightGroup` targets the physical right column; neither toggles or cycles. A command for the already-active side is a no-op. Directional focus uses that column's retained selected/top available member and MUST NOT change any column's retained selection as a side effect.

### COL-008 — Divider

Divider ratio is per Space, physically directional, bounded by configuration, retained through layout switches, and reset only by explicit reset or cold state initialization. The current composition MUST bound the ratio to 0.30–0.70: four 0.05 steps from 0.50 in either direction; further outward commands leave it at the bound. This fixed limit is the user-approved TODO0005 mitigation (2026-10-15), not adaptive native minimum-size enforcement or a containment guarantee for every window/display.

### COL-009 — Cold bootstrap

When an untracked Space is first adopted in columns mode, eligible windows are ordered by observed creation time when trustworthy, otherwise ascending native window ID as a deterministic approximation. All but the newest enter the left stack; only the newest enters the right. The actually focused managed member determines the active column.

### COL-010 — Uniform configurable gaps

Public top-level `columnGap` MUST be finite nonnegative points, defaulting to 0. Columns projection MUST apply the same gap on all outer sides of the usable area and once (not doubled) between available columns. The top gap starts below the usable-area boundary, not the display top. A single available column receives outer gaps only. The retained ratio divides the window width remaining after gaps (usable width minus `3 * gap` for two available columns); projection MUST NOT change ratio, membership or selection. Stack projection applies the same configured outer gap, as specified by STACK-001. The effective gap MUST be clamped to `min(columnGap, usableWidth / (twoAvailableColumns and 3 or 2), usableHeight / 2)`. Dimensions MUST remain nonnegative; extreme settings MAY produce zero-sized frames. This geometric fit bound does not enforce native window minimum sizes.

## Focus

### FOCUS-001 — Separate focus concepts

Actual macOS focus, managed layout selection, and managed global focus history are distinct. An unmanaged actual focus MUST NOT update managed selection/history.

### FOCUS-002 — Commands during unmanaged focus

When a popup/excluded window has actual focus, layout/Space commands remain available. `j`/`k` starts from the last managed selection in the active stack on the current regular Space. Commands that require a managed target MUST reject an unmanaged target.

### FOCUS-003 — Focus does not admit

An actual focus callback MUST NOT admit an unknown window. It MAY trigger one targeted ownership/readiness probe; only that independently confirmed result emits an idempotent admission event. Admission otherwise occurs through creation/readiness, restore/unhide, startup bootstrap, or confirmed regular-Space entry.

### FOCUS-004 — Close/minimize recovery

After the focused managed member becomes unavailable, recovery preference is:

1. most recently confirmed focused available survivor in the source stack/column; if none has confirmed focus history, the last available survivor in stable membership order;
2. the retained selected available member in the other column;
3. no focus request.

Focus recency is filtered to surviving members of the physical source after structural normalization, not an opener relationship or admission-time snapshot. It MUST NOT reorder membership or the `j/k` cycle. The same preference applies to close/minimize and future source recovery; unavailable/dead entries are skipped. Recovery MUST NOT cross Spaces. A transient native fallback focus observed between close/minimize and the authoritative removal/unavailability event MUST NOT redirect recovery to another column. A background close/minimize MUST preserve the current managed focus and every column's retained selection.

### FOCUS-005 — Global previous window

The previous-window command uses managed global focus history only. It may cross Spaces, unminimize a window, unhide its application, or enter its native fullscreen Space. Repeated invocation toggles according to actual managed focus observations. Independently admitted native-fullscreen windows participate even when they have never had a regular layout slot. Readiness alone MUST NOT insert or reorder history. Dead entries are skipped/removed.

### FOCUS-006 — Effect ordering and mouse focus

A requested focus MUST NOT revise membership/order. Desired managed focus and actual macOS focus are distinct. While a managed focus request is pending, stale actual-focus callbacks MUST NOT overwrite its desired selection. A matching actual-focus observation confirms the request. When no managed focus request is pending, a mouse/native actual-focus observation of a managed window MUST immediately update that Space's active group and that group's selected/top member; the next `h`/`l`/`j`/`k` command MUST act from that observation on its first invocation.

## Availability and native lifecycle

### LIFE-001 — Minimize

Native minimize marks one managed window unavailable, retains its slot, excludes it from `j`/`k` and bar available count, and keeps it in the chooser. Explicit chooser/previous-window selection MAY unminimize it.

### LIFE-002 — Application hide

Native app hiding sets an `appHidden` condition for every managed window of that app without simulating or clearing minimize. Slots remain. Unhiding clears only `appHidden`; a still-minimized/fullscreen member remains unavailable. Chooser selection may unhide the app.

### LIFE-003 — Rule decision stability

Eligibility/exclude/fullscreen-on-create rules are evaluated once when creation metadata is ready. Title/metadata changes update presentation but MUST NOT reclassify or reorder an admitted window.

### LIFE-004 — No destructive reconciliation

There is no periodic reconciliation that prunes from an onscreen/eligible snapshot. Any safety polling requires a recorded POC proving a silent gap and a non-destructive targeted algorithm.

## Native fullscreen

### FS-001 — Definition

“Native fullscreen” means macOS native fullscreen in a dedicated fullscreen Space. Stack layout is not called fullscreen; it is a regular Space layout with visible decorations/bar.

### FS-002 — Manual fullscreen retention

An already admitted window entering native fullscreen retains its exact saved placement. Its source projects remaining available members without requesting recovery focus behind the fullscreen window. Exiting restores the slot if the original regular Space still exists and remains the actual destination.

### FS-003 — Removed source

If the saved source Space is removed while a window is native-fullscreen, that placement is invalidated. On exit, macOS actual destination is authoritative and the window is newly admitted there.

### FS-004 — Fullscreen-on-create

A creation rule requests native fullscreen before tiling. While fullscreen the managed window has no normal layout slot. If the request fails, admit normally. On manual exit, newly admit it on its actual regular Space. Do not create a dedicated desktop in MVP.

### FS-005 — Bar and navigation

Native fullscreen/tiled Spaces are excluded from numbered regular desktops. The custom bar is hidden there. Native-fullscreen managed windows remain in chooser/history but are unavailable to `j`/`k`.

## Regular desktop Spaces

### SPACE-001 — Native positional numbering

Desktop numbers are the current left-to-right positions of regular user Spaces only. Deletion/reordering renumbers positions exactly as macOS does. Fullscreen/tiled Spaces are excluded.

### SPACE-002 — Numbered shortcuts focus only

Numbered desktop shortcuts focus an existing regular desktop. They MUST NOT create a missing number.

### SPACE-003 — Dedicated creation command

A separate configurable command creates one next contiguous native regular desktop and focuses it. It does not create gaps or multiple intermediate desktops.

### SPACE-004 — Cyclic positional navigation

Previous/next desktop commands navigate regular positions cyclically and skip native fullscreen/tiled Spaces.

### SPACE-005 — Confirmed history

10bucks retains current and previously active regular Space IDs only after confirmed native activation. The previous-desktop command (default digit `0`) focuses the previously active existing regular desktop; after confirmation, another invocation toggles back. Repeated invocation before confirmation targets the same previous desktop. Missing history is a no-op/rejection, never creation. A confirmed departure from a regular desktop into native fullscreen/tiled makes that departed regular desktop the previous-desktop target; the fullscreen/tiled identity itself never enters regular-desktop history. Thus D2 → D1 → fullscreen makes `0` target D1, while cyclic next still resolves from D1 and targets D2. Repeated fullscreen observations must not overwrite the departed target. Returning to that same regular desktop preserves the earlier other regular desktop for subsequent toggling; entering a different regular desktop makes the departed regular desktop its previous target. History tracks native identity across reordering, not numbered position. This history does not change SPACE-004 behavior.

### SPACE-006 — Native authority and removal

Native Space topology/membership is authoritative. Removing a Space deletes its complete 10bucks state and invalidates saved placements that point to it. Manual Mission Control removal is handled the same way.

### SPACE-007 — Empty deletion

Deletion starts only when a POC-validated native observation says the current regular Space has no ordinary application windows. Excluded/future-floating ordinary windows count as non-empty; system overlays/transient surfaces do not. A former member currently in a native fullscreen Space does not make its old regular Space non-empty.

### SPACE-008 — Deletion destination

Before removing the active empty Space, destination preference is:

1. globally previous live managed window whose actual target Space is confirmed and differs from source;
2. previously active existing regular desktop;
3. adjacent regular desktop, preferring left then right.

Skip an absent/uncertain/source-resolving candidate before issuing effects. If an issued destination fails to leave the source, abort instead of cascading to another potentially late effect. After confirmed source inactivity, immediately recheck that the source still exists, remains inactive, and is still natively empty before removal. Abort on changed or uncertain facts. Because the native check and removal are not assumed atomic, a later observed native change remains authoritative and MUST be reconciled. The only regular desktop cannot be removed.

### SPACE-009 — External changes

Manual Space reorder/create/delete and manual window-to-Space movement MUST update 10bucks from observed native topology; they MUST NOT leave ghost scopes or membership.

### SPACE-010 — Keyboard move without following

A move-to-desktop command targets the actually focused managed window on the current regular desktop and an existing regular desktop position. It moves the window without activating the destination, integrates it into that desktop's layout, and tiles it there. Source focus recovery MUST use the same source-stack/column preference as focused destruction (FOCUS-004 and COL-005). Destination admission MUST NOT request focus across Spaces. The old source column/slot does not follow the window; the confirmed native destination receives normal layout admission. Moving to the current desktop is a no-op; a missing destination never creates a desktop. Native-fullscreen windows and fullscreen/tiled destination Spaces are outside this command's initial scope. Native movement and inactive-desktop frame application require recorded evidence before implementation relies on them.

## Rules

### RULE-001 — Ordered rules

Rules are ordered and first-match-wins. Matching uses normalized metadata. Current terminal actions are `manage`, `exclude`, and `nativeFullscreenOnCreate`.

### RULE-002 — Generic default

Default eligibility is based on generic AX role/subrole/modal/move/resize capabilities and self-process exclusion, not external bundle IDs. A confirmed native-fullscreen owner plus a true native-fullscreen property permits locked AX position for an otherwise standard, nonmodal, resizable foreign window; it is managed without inventing a regular layout slot. Ordinary immovable windows remain excluded. This mode-specific distinction is supported by POC-010.

### RULE-003 — Predicate boundary

Optional predicates receive immutable normalized metadata. They MUST NOT receive an `hs.window` or perform hidden global scans through the rule engine.

### RULE-004 — Bootstrap is not creation

`nativeFullscreenOnCreate` applies only to genuine post-start window creation. Pre-existing windows discovered during startup/Space activation still evaluate manage/exclude policy but MUST NOT be forced fullscreen.

## Discovery

### DISC-001 — Bounded regular-desktop cold bootstrap

MVP performs one bounded best-effort startup discovery across regular desktops, without activating those desktops or requesting focus. Native inventory is a discovery hint, not management or liveness proof; each admission requires confirmed native ownership, eligibility and exact resource identity. Unresolved candidates remain unknown, never guessed, excluded or removed merely to claim completeness. Startup records attempt settlement separately from complete resolution. Confirmed managed chooser rows remain usable while discovery is pending or incomplete; the chooser MUST NOT add discovery warnings or block opening. Regular-desktop activation and native lifecycle events continue incremental discovery afterward, without permanent retry polling. This user-approved MVP does not guarantee every pre-existing window is resolved at cold start. Fullscreen/minimized cold-start discovery remains deferred to TODO0003; already discovered unavailable members retain their existing state.

### DISC-002 — Uncertain unavailable windows

A pre-existing minimized/hidden window is admitted only when its actual regular Space is confirmed. Otherwise it waits until restore/unhide or a focus-triggered targeted ownership/readiness probe emits an independent admission event. `ActualFocusChanged` itself never admits. Duplicate/delayed readiness results are idempotent. A pre-existing native-fullscreen window MUST be tracked once independent ownership/readiness confirms its eligibility. Until actual regular ownership is confirmed it has no normal layout slot. On exit it is admitted to that actual regular Space, preserving its existing rule decision and history position. Unknown exit ownership remains unplaced, not guessed. Startup on native fullscreen MUST NOT invent a regular Space or request focus.

### DISC-003 — Global means discovered

Cross-Space chooser/history scope covers all discovered managed windows. It MUST NOT trigger a global scan to promise windows the platform has never exposed to 10bucks.

## Chooser

### CHOOSE-001 — Managed scope

Chooser lists discovered managed windows only, across regular and native-fullscreen Spaces, including minimized and app-hidden windows with confirmed ownership. Excluded/transient/undiscovered windows are absent.

### CHOOSE-002 — Cached backend

Opening chooser MUST use incrementally cached rows and perform no global AX/window enumeration or per-window icon lookup.

### CHOOSE-003 — Stable admission order and ranked search

Surviving cached rows keep stable admission rank. New managed windows append; destroyed windows disappear; focus, title, availability, layout, and Space changes do not reorder that underlying order. An empty query presents admission order. A nonempty query presents matches by relevance, using admission order as the final tie-breaker; search MUST NOT mutate cached order or membership.

### CHOOSE-004 — Ranked fuzzy search and existing UI

Keep `hs.chooser` and its observed `Cmd+1…9` current-visible-row selection behavior. Search matches ordered characters literally in title or application name, and ranks exact-field, word-boundary contiguous, other contiguous, word-boundary-start subsequence, then other subsequence matches. Within a class, fewer intervening characters then earlier start wins. Compare each field independently; prefer application-name matches on identical field quality, then stable admission order between rows. A weaker application match MUST NOT outrank a stronger title match merely because of its field. Word boundaries use field start or preceding ASCII whitespace/punctuation; current ASCII case-insensitivity remains. Unicode character distances are supported, but Unicode case folding, normalization and word segmentation are not promised. UI styling is not an MVP rewrite target.

## Bar

### BAR-001 — Spaces and native UI

One overlay-level canvas joins all regular Spaces and remains visible in Mission Control/App Exposé. It is hidden on native fullscreen/tiled Spaces. macOS can pin a canvas that still has `canJoinAllSpaces` to a subset of Spaces. Showing it again does not fix that, but a fresh canvas does. So once per regular-Space arrival (and after handoff), a settled check (one-shot, 0.5 s) replaces an occluded canvas that should be visible. This is not a poll.

### BAR-002 — Native menu-bar handoff

The macOS menu bar is configured to auto-hide. Pointer entry into the custom top strip hides the custom bar; it returns after the pointer leaves and a short grace period. Only temporary pointer tracking may run while hidden.

### BAR-003 — Content

The bar shows active layout, regular desktop positions, actual focused window title/application, available position/count in the current managed stack, and date/time.

### BAR-004 — Actual focus title

If an unmanaged popup/excluded window has actual focus, the bar shows that actual title/application while retaining the active managed stack context for count/navigation.

### BAR-005 — Available count

Position/count includes only currently available members accessible via `j`/`k`. Unavailable durable members remain ordered state but are omitted from the displayed sequence.

### BAR-006 — Event-driven updates

Focus/title, reducer state, Space, appearance, and screen events drive updates. Clock updates use a minute-boundary timer. There is no permanent 150 ms full bar refresh.

### BAR-007 — Theme

Light/dark appearance behavior remains supported. Unchanged view models MUST NOT reorder/show/render the canvas again.

### BAR-008 — Content alignment

The bar MUST retain its 32-point height. Text MUST align visually with the native privacy dot, and layout icons MUST align with the rendered text centre. Text uses a +5-point downward shift and icons a +3.5-point shift relative to the original positions; equal frame offsets do not imply equal rendered centres. Pure frame checks do not prove native visual alignment.

## Commands and feedback

### CMD-001 — Keyboard configuration

MVP commands have configurable native Hammerspoon hotkeys. Binding code is a thin command adapter.

### CMD-002 — Success feedback

Successful commands MUST NOT show transient alerts. The bar is normal feedback. Rejected/impossible operations MAY show one actionable error.

### CMD-003 — Immediate layout effects

Managed frame animations are removed. Layout frame effects use duration zero and are deduplicated.

### CMD-004 — Removed modal

The legacy `Hyper+u`, then digit workspace-selection modal is not part of MVP. Numbered focus and dedicated create/delete/navigation commands replace it.

### CMD-005 — Rapid focus/navigation

Repeated stack/group focus commands reduce against committed desired selection; every keypress counts and the newest focus request is authoritative. Relative desktop `n/p` advances from the pending desired destination (`n,n` from 1 desires 3; `n,p` desires 1), while numbered focus replaces it absolutely and native switches execute serially. Latest chooser target wins. Repeated previous-window before actual focus confirmation resolves from unchanged actual history and targets the same previous window.

### CMD-006 — Structural operation serialization

A second create/delete Space or same-target fullscreen mutation is rejected while that structural operation is pending. Any command that would change regular Space is rejected during create/delete; same-Space layout/focus remains available. Timeout clears intent and resnapshots actual state. Late OS changes are external observations, not completions of expired intent.

## Persistence

### PERSIST-001 — Memory-only MVP

MVP layout state is memory-only. macOS logout/reboot and Hammerspoon environment reload reset it. No persistent layout cache, migration, or cross-reboot identity matching is implemented.

### PERSIST-002 — Deferred reload handoff

A one-shot, immediately deleted reload snapshot is a separate follow-up after state schema stabilizes. It is not an MVP requirement and MUST NOT introduce compatibility migrations.

## Performance

### PERF-001 — Idle work

Idle layout/window/Space queries are zero. The minute clock timer and bounded/transient operation timers are allowed.

### PERF-002 — Snapshot complexity

One transaction may take one necessary relevant snapshot and build an ID map. Layout loops MUST NOT call `hs.window.get`, `allWindows`, or equivalent global enumeration per member.

### PERF-003 — Frame writes

One transaction writes at most one deduplicated frame per affected window. A created window MUST NOT receive a temporary wrong-column 10bucks frame before its final placement.

### PERF-004 — Budgets

Latency and measurement gates in [`performance.md`](performance.md) are release criteria, not optional profiling advice.

## Explicitly deferred

The following are not MVP invariants:

- multiple displays
- managed floating mode
- CLI/skhd control
- persistent state or reload snapshots
- dedicated desktop after spawn-fullscreen exit
- configurable third-party bar/layout plugin distribution
- support shims for other macOS/Hammerspoon versions

## Current delivery priority

The current user-approved remaining order is recorded in [`development-roadmap.md`](development-roadmap.md). Existing-desktop switching (positions 1–9 and previous-desktop on 0) comes first, then creation and configured rules. Keyboard move-to-desktop without following and desktop deletion are deferred by the October 11 decision; SPACE-010 and SPACE-007/008 remain their future target contracts, not implemented or waived safeguards. Positions beyond nine remain reachable through cyclic navigation; 0 is not position ten.
