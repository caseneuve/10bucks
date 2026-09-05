# macOS Environment Contract

> **Status: target MVP setup.** Exact labels/paths and reliable detection must be verified on the supported macOS build by the settings POC. 10bucks does not change system settings automatically.

## Supported baseline

- macOS 26.x on Apple Silicon
- Hammerspoon 1.1.1
- built-in display only
- SIP enabled
- Accessibility permission granted to Hammerspoon

The project currently has one user. Supporting other versions through compatibility branches is a non-goal.

## Required settings

### Hammerspoon Accessibility access

Hammerspoon needs Accessibility permission to observe and manipulate other applications' windows.

Use System Settings search for **Accessibility**, then enable Hammerspoon under Privacy & Security. This permission cannot be granted safely/programmatically by 10bucks.

### Automatically hide and show the menu bar: Always

The custom bar occupies the native menu-bar area. The native menu bar must auto-hide so the custom bar can normally render there and temporarily hand the area back on pointer hover.

Use System Settings search for **Automatically hide and show the menu bar** and choose **Always**. Exact navigation labels may change across macOS builds.

### Automatically rearrange Spaces based on most recent use: Off

10bucks desktop numbers are native left-to-right regular-Space positions. Automatic rearrangement would change those positions unexpectedly.

Use System Settings search for **Automatically rearrange Spaces based on most recent use** and turn it off.

## Conditional setting

### Native “Switch to Desktop N” shortcuts

The Space-switch POC will compare native numbered shortcuts with `hs.spaces.gotoSpace()`. If native shortcuts are selected as the production switching mechanism, the required Mission Control shortcuts must be enabled and non-conflicting.

Do not document this as required until that POC selects the path and verifies exact macOS 26.x behavior.

## Recommended settings

### Displays have separate Spaces: On

Hammerspoon's `hs.spaces` documentation recommends this setting. It is currently enabled. MVP uses only the built-in display, but keeping it enabled avoids changing the Space model when external-display support is explored later.

Changing this setting may require logout. 10bucks MUST NOT change it automatically.

### Reduce Motion: optional

Hammerspoon documents that Reduce Motion can reduce, but not eliminate, visual Mission Control side effects during Space selection/creation/removal. It is optional and should be evaluated in the Space POC rather than silently required.

## Settings/features requiring POC classification

Do not guess their effect. The environment POC must classify each as supported, unsupported, irrelevant, or optional:

- Stage Manager
- macOS native edge-drag/window tiling
- “When switching to an application, switch to a Space with open windows for the application”
- any separate menu-bar auto-hide setting for fullscreen
- native desktop shortcut availability after dynamic Space creation/deletion

Dock auto-hide currently appears unrelated to 10bucks correctness and should not become a requirement without evidence.

## Read-only doctor script

A cheap follow-up to the settings POC may add:

```sh
./scripts/doctor
```

It is diagnostic only. Example output:

```text
PASS     Hammerspoon 1.1.1
PASS     Accessibility granted
PASS     Menu bar auto-hide enabled
FAIL     Automatic Space rearrangement enabled
         Fix: search System Settings for “Automatically rearrange Spaces…”
UNKNOWN  Stage Manager state on this macOS build
```

Requirements:

- report `PASS`, `FAIL`, or `UNKNOWN`; never turn uncertainty into success
- explain why a failed setting matters
- link/name the System Settings control
- MAY open the relevant System Settings pane after explicit user action
- MUST NOT run `defaults write`, restart Dock/SystemUIServer, log out, or mutate TCC permissions
- MUST treat undocumented `defaults read` keys as version-specific POC evidence, not stable public API

## Currently observed values

These observations are evidence for this machine, not a portable detection contract:

```text
mru-spaces = 0                       # automatic rearrangement off
_HIHideMenuBar = 1                  # menu bar auto-hide enabled
hs.spaces.screensHaveSeparateSpaces() = true
SIP = enabled
```

The doctor implementation must be selected only after toggled A/B tests prove what each detectable value means on the supported build.
