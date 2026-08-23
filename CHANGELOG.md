# Changelog

All notable changes to 10bucks are documented in this file.

The project uses UTC date versions in the form `YYYY.MM.DD`. Pre-releases
append `-alpha.N`, for example `2026.08.22-alpha.1`; a second stable release
on the same date appends `.N`, for example `2026.08.22.2`.

## [Unreleased]

## [2026.08.23-alpha.3] - 2026-08-23

### Added

- Added `bar.menuBarHideDelay` and `bar.menuBarFadeDuration` options for the custom-bar/native-menu-bar handoff.
- Added event-driven per-screen workspace-label caching, with a one-second TTL as a resilience fallback.

### Changed

- The custom bar now hands off at the native menu-bar window level, hides and fades during menu-bar reveal, and returns without continuously reordering visible canvases.
- Workspace-label cache entries are invalidated by workspace mutations and Spaces watcher events while preserving optimistic pending-workspace feedback.
- Chromium/Electron missed-close reconciliation now uses cheap onscreen window-ID snapshots instead of repeated Accessibility lookups, reducing reconciliation overhead.

### Fixed

- Focus recovery after window close or minimize now uses actual focused-window state, is limited to the active workspace, and retries only a bounded number of times.
- Cross-Space chooser and previous-window focus now switch to the destination Space before focusing, avoiding focus-manager races that briefly select the target and then return to a transient Contexts window.

## [2026.08.23-alpha.2] - 2026-08-23

### Added

- Local development install workflow via `just install` or `scripts/install-local.sh`.
- Security policy for private vulnerability reports.

### Changed

- Include the MIT license in the distributed Spoon archive.
- Identify the Spoon author as `caseneuve`.
- Document the tested Hammerspoon version.

## [2026.08.23-alpha.1] - 2026-08-23

### Changed

- Reordered the status bar to show workspaces and the focused window title before the stack position.
- Modal and fixed-size standard windows now float instead of being managed.

## [2026.08.22-alpha.1] - 2026-08-22

### Added

- First alpha release of the 10bucks Hammerspoon Spoon.
