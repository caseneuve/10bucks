<p align="center">
  <img src="assets/10bucks-logo.png" alt="10bucks logo" width="160">
</p>

# 10bucks — Canary A candidate

10bucks is an opinionated, keyboard-first macOS tiling-window-manager rewrite built on [Hammerspoon](https://www.hammerspoon.org/). This checkout is the **Canary A candidate**, not a general release and not a replacement that may be switched on without approval.

Canary A manages the confirmed original regular Space with the replacement direct-AX event path and stack projection. It is intentionally narrow: it is for scheduled, disposable-window acceptance after explicit human approval.

## Included in this candidate

- Direct application/UI-element AX lifecycle observation for the active original regular Space.
- Stack navigation and zero-duration reflow effects.
- Twelve configurable Hyper bindings: `Space` (cycle), `h/l` (column focus), `j/k` (window focus), `'` (previous managed window), `o` (move window), `g` (swap columns), `[/]` (resize divider), `=` (reset divider), and `r` (reflow).
- A required explicit built-in-display UUID preflight before startup.

## Explicitly absent

Canary A does **not** include a bar, chooser, native-Space commands or navigation, fullscreen commands/effects, configured rules, columns controls, legacy workspace/modal controls, or compatibility behavior. Do not rely on legacy documentation or older releases for this candidate's behavior.

A confirmed switch away from the original regular Space suspends this candidate non-destructively. It does not adopt or manage the new Space. Commands reject while suspended; returning to the original confirmed Space restarts observation and retains the original replacement Core state.

## Requirements and switch gate

- macOS 26.x on Apple Silicon, Hammerspoon 1.1.1, SIP enabled, and the built-in display; see [macOS settings](docs/macos-settings.md).
- Accessibility access granted to Hammerspoon.
- A verified built-in display UUID placed in the config before startup.
- **Explicit human approval** for the duration and disruption of a Canary A switch. Normal development must not install, reload, repoint the Spoon symlink, or start this runtime.

Before any approved switch, capture the stable runtime target and semantic baseline, stop it completely, then load only the candidate. Restore stable after the session unless approval explicitly says otherwise. See [the rewrite plan](docs/rewrite-plan.md) for the required canary/rollback process.

## Candidate configuration

Copy `10bucks.spoon/config.example.lua` to `~/.config/10bucks/config.lua`, replace the placeholder with the UUID recorded during the approved switch preflight, and keep only the supported `hotkeys` entries. The UUID is machine-specific: do not commit it.

```lua
local hyper = { "cmd", "alt", "ctrl", "shift" }
return {
  builtInDisplayUUID = "UUID-FROM-APPROVED-PREFLIGHT",
  hotkeys = {
    cycleLayout = { hyper, "space" },
    focusLeftGroup = { hyper, "h" },
    focusRightGroup = { hyper, "l" },
    focusNext = { hyper, "j" },
    focusPrevious = { hyper, "k" },
    focusManagedPrevious = { hyper, "'" },
    moveFocusedToOtherGroup = { hyper, "o" },
    swapGroups = { hyper, "g" },
    resizeLeft = { hyper, "[" },
    resizeRight = { hyper, "]" },
    resetRatio = { hyper, "=" },
    reflow = { hyper, "r" },
  },
}
```

Set one of these twelve named bindings to `false` to disable it. No other configuration keys or bindings are supported by Canary A.

## Rewrite contracts

The target contracts remain authoritative; they describe the approved rewrite, not all behavior implemented by this candidate:

- [Target invariants](docs/invariants.md)
- [Architecture](docs/architecture.md)
- [Rewrite plan](docs/rewrite-plan.md)
- [Performance contract](docs/performance.md)
- [POC evidence policy](docs/pocs/README.md)

## Development checks

Pure/fake checks do not authorize a live switch:

```sh
lua tests/run.lua
git diff --check
```

Do not run the local install script or reload Hammerspoon from this rewrite worktree without the approval described above.
