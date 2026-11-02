# POC-026 — Visible-column availability normalization

## Approved correction
On 2026-11-01 the user rejected unavailable durable stacks counting as hidden
columns: columns means visible columns. Minimizing the last available member of a
column must normalize available survivors just like deleting its last member.
COL-001–005 and WIN-002–004 now record that correction. Managed unavailable
windows remain retained; normalized survivors are not moved back on restore.

## Verified implementation and native scope
`columns.lua` owns reducer normalization and visible-occupancy admission. Core
forwards availability changes through existing layout capability dispatch, before
projection/effects. No adapter scan, polling, native mechanism, or host reload was
added. Stack does not handle this layout-specific event.

Reused owned guest `10bucks-run-ft-eaa07ef31097`: fresh Accessibility granted,
Secure Input off, no loaded manager, three preexisting windows. Frozen source,
controller and existing owned AppKit fixture used fixture-title-only management;
preexisting windows remained excluded. Native minimize/unminimize used existing
Hammerspoon methods; explicit fixture focus modeled the user's focus action.

Native frame readback verified:
- one available survivor becomes full width;
- new admission recreates two visible columns despite retained minimized member;
- background left-column loss rebalances survivors without stealing focus;
- sole right-column minimize re-splits available survivors;
- restore, explicitly focus, minimize again retains the visible split;
- subsequent admission retains split and receives actual native focus.

This is native geometry evidence, not screenshot/pixel inspection, physical-host
acceptance, keyboard delivery, or latency certification. Pure regressions cover
minimize, hide, fullscreen, right-only admission, restore retention, unavailable
replacement filtering, and committed split-frame intents: **359 Lua tests pass**.

## Preserved failures and qualification
Runs 1–2 had controller assumptions wrong: survivor stable order after B then C
admission, then assuming unminimize preserved native focus. Those failures remain
unchanged. Run 3 failed focused recovery; run 4 captured native/state diagnostics:
frames were correctly split but native focus and active selection landed left
instead of on the supplied right replacement. This is a real unresolved focus
qualification, not a layout pass. Run 5 explicitly scoped the geometry oracle and
still measured focus separately: sole-right minimize recovery false, subsequent
restore/focus/minimize recovery true. No corrective effects manufactured a pass.
No product-source changes between native runs. Do not interpret the run-5
`passed` field as complete FOCUS-004 acceptance.

Ignored evidence: `.pi/visible-columns-native-r{1,2,3,4,5}.json`, frozen directories
`.pi/visible-columns-freeze-r{1,2,3,4,5}/`, hash manifests
`.pi/visible-columns-r{1,2,3,4,5}.sha256`, controller
`.pi/visible-columns-native.lua`. Diagnostic artifacts contain fixture-only
geometry and aliases, no user-window content or native identities.

Each fixture quit acknowledged/normal exit, mailbox claims absent; candidate and
controller timer stopped, captured validity/discovery resources drained. Final
independent guest observation retained exactly three preexisting windows. Host
running frozen candidate was not modified or reloaded.

## Remaining action
Resolve transient native fallback versus focused minimize recovery before claiming
complete FOCUS-004 acceptance. Host deployment requires separate user authority;
the visible-column patch has not been loaded on the host.
