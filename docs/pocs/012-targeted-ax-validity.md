# POC-012 — Exact AX validity after an unreported close

## Status
Verified narrow mechanism, October 10, 2026. Production acceptance pending.

## Decision enabled
On a focus-event boundary, check the retained AX element of the previously focused managed window. An application AX focus event also checks that application's current retained window resources; this avoids losing the invalid target when an earlier callback has already replaced actual presentation. Explicit `isValid() == false` may normalize removal for that resource before fallback focus is reduced. No global scan or permanent poll.

## Evidence and procedure
Legacy was sole manager. Human created a Ghostty window using Hyper+Return and closed it first with Ctrl+D, then a separately created window with Cmd+W. Before each close, an app-local before/after enumeration identified exactly one new window by native AX equality. The exact new element was retained and observed through both `hs.window:newWatcher` and `hs.axuielement.observer`; explicit destruction registration succeeded. Observers were stopped after each result. No agent window close, Space operation, settings change or runtime replacement occurred.

Both closes produced zero destruction callbacks through either observer, while the exact retained AX element returned `isValid() == false`. App-local absence was corroboration only, not removal authority. Private primitive results: `.pi/close-comparison-ctrl-d.json` and `.pi/close-comparison-cmd-w.json`.

Earlier timed/wrong-target attempts are inconclusive and do not establish silent destruction. The Ctrl+D-versus-Cmd+W difference hypothesis is not supported by these two successful target-joined observations.

## API/source basis
Installed API documents `hs.axuielement:isValid()` as boolean, or nil/error for other AX failures. Hammerspoon source `extensions/axuielement/libaxuielement.m` implements false only for `kAXErrorInvalidUIElement`; a successful AXRole read returns true, other errors return nil/error. Retain the original element rather than reconstructing an element from a dead window wrapper.

## Limits and production consequence
Two ordinary closes on this environment, not broad app reliability or PID/window-ID reuse proof. Invalid AX means this observed AX resource ended, not that no replacement native window can exist. The resource guard/removal applies only to its retained lease. True, nil, thrown errors and snapshot absence never remove membership.

Event-triggered validity does not solve background closes without a relevant event. Checking all retained windows of the event application has cost proportional to that app's managed members; it is not an app-window enumeration and still requires performance measurement. Source tests cover close-before-fallback ordering, unavailable reads and exact resource cleanup; live candidate acceptance remains necessary. No app-specific production branch is permitted.
