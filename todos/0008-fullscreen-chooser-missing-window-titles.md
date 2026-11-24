---
title: Known fullscreen chooser rows lack window titles
status: open
priority: high
type: bug
labels: []
created: 2026-10-15
parent: null
blocked-by: []
blocks: []
---

## Context

**User-observed:** on the frozen d3d9e29 host candidate, discovered native-fullscreen
Signal and Slack windows appear in the chooser without window titles; only the
application/class label is shown. These are the only fullscreen apps currently
listed. Other live fullscreen apps are absent; the user suspects they have not
been focused since the last Hammerspoon reload. That discovery explanation is a
hypothesis, not a verified inventory or focus history.

Keep two outcomes separate: missing metadata for known rows is this bug; absent
fullscreen rows/cold-start discovery remains TODO0003. Signal/Slack are reproduction
context, never production policy. TODO0004 delivered selection of known fullscreen
rows, not external-app title reliability. Its generic native fixture titles passed.

**Verified source:** init.lua:_cacheReady stores event.title or an empty string;
WindowTitleChanged updates exact-lease chooser rows. window_host.lua reads native
window titles on readiness/title notifications. The chooser displays cached title
and application name separately. No raw native read proves whether these affected
windows expose a nonempty title, or whether acquisition/event/cache handling loses it.
**User-confirmed:** visiting Signal/Slack and reopening the chooser still leaves
these titles blank. A simple first-visit metadata delay is therefore insufficient
to explain the reported persistence; native title availability remains unverified.

## 2026-11-24 host observation

The user reported the same blank-title symptom for Cloudflare WARP. Read-only
checks on the exact live managed window found an empty native AXTitle and
Hammerspoon title, an empty cached/projected chooser title, and a nonempty app
label. The window was on a regular Space and neither native fullscreen check
reported fullscreen. This case shows no dropped native title and does not resolve
the earlier fullscreen Signal/Slack reports. No private title text was recorded.

User decision: display the cached app label in brackets when the native title
is blank. This is display-only: it does not change search or title acquisition.
A guest native chooser check passed for a synthetic blank row and a named control
(`vm/results/10bucks-run-ft-eaa07ef31097/chooser-blank-title/`).

## Acceptance Criteria

- [ ] Distinguish an actually empty/unavailable native title from a nonempty title
      lost during exact-resource readiness, title events or chooser caching. Keep
      private title content out of committed evidence; use equality/presence facts.
- [ ] A known managed fullscreen window with a confirmed nonempty native title
      shows that title in its cached chooser row, for retained and unplaced ownership.
- [ ] Later confirmed title changes update the same exact-resource row without
      reordering admission, changing rules/placement, requesting focus or scanning
      globally on chooser invocation.
- [ ] Define truthful presentation for genuinely empty/unavailable native titles;
      do not invent window content or add app-specific branches/polling workarounds.
- [ ] Cover generic readiness/title-event/resource sequences and targeted native
      acceptance for the diagnosed boundary; retain uncertainty and preserve title
      updates across relevant observer/Space transitions.

## Affected Files

- `10bucks.spoon/init.lua` — cached readiness/title event routing.
- `10bucks.spoon/lib/macos/window_host.lua` — exact native title acquisition/observer.
- `10bucks.spoon/lib/window_chooser.lua`, `lib/macos/chooser.lua` — cached presentation.
- `tests/`, `functional-tests/` — generic fullscreen metadata/resource coverage.
- Relevant contracts: CHOOSE-002/003/004, FOCUS-003, LIFE-003, STATE-003/007.

## E2E Spec

GIVEN an independently confirmed managed native-fullscreen window whose exact native
resource reports a nonempty title, WHEN its cached row is displayed in the actual
chooser, THEN the row contains that title and its application label. A confirmed
subsequent title change updates the same row without focus, membership/order or
fullscreen effects. Unknown fullscreen-window discovery is not required by this case.

## Notes

Tracking only following the user report; no runtime fix, host reload/window/Space
action or queue reprioritization authorized by this record. Cold-start discovery
remains TODO0003; regular wrong-member focus remains TODO0007. Visiting/reopening
has been confirmed not to repair the title; do not infer native title availability,
a missed notification or an acquisition race from that observation alone. Existing cached metadata/resource owners should be reused; no new registry,
permanent timer, app-specific policy or chooser-time enumeration.
