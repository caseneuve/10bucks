<p align="center">
  <img src="assets/10bucks-logo.png" alt="obligatory AI generated logo that makes no sense" width="160">
</p>

# 10bucks

Opinionated macOS tiling window manager built on
[Hammerspoon](https://www.hammerspoon.org/).  Pure vibe slop.  GPT Terra wrote it for me
for $10.  Works, all things considered.

## Features

- Tabbed stacks and two-column window layouts.
- Keyboard-driven focus, layout, and divider controls.
- Native macOS Space navigation, creation, and removal.
- Configurable rules to open matching new windows in native macOS fullscreen.
- A per-display status bar with workspace and layout state.
- A fuzzy window picker and global previous-window focus.

## Requirements

- macOS with Hammerspoon (tested on 1.1.1).
- Accessibility access granted to Hammerspoon.

## Install

1. Install [Hammerspoon](https://www.hammerspoon.org/) and grant it Accessibility access.
2. Download [`10bucks.spoon.zip`](https://github.com/caseneuve/10bucks/releases/latest/download/10bucks.spoon.zip) from the latest release. Uncompress it if your browser does not, then double-click `10bucks.spoon` in Finder.
3. Create your configuration from the installed example:

   ```sh
   mkdir -p ~/.config/10bucks
   cp ~/.hammerspoon/Spoons/10bucks.spoon/config.example.lua ~/.config/10bucks/config.lua
   ```

4. Add this to `~/.hammerspoon/init.lua`:

   ```lua
   local tenbucks = hs.loadSpoon("10bucks")
   tenbucks:configureFile()
   tenbucks:bindHotkeys()
   tenbucks:start()
   ```

Edit `~/.config/10bucks/config.lua`, then reload Hammerspoon. The installed `config.example.lua` documents every available setting.

## Default controls

All defaults use `Hyper` (`cmd` + `alt` + `ctrl` + `shift`).

| Key               | Action                                           |
|-------------------|--------------------------------------------------|
| `space`           | Toggle one tabbed stack / two columns            |
| `h` / `l`         | Focus previous / next column                     |
| `;`               | Focus the previously focused standard app window |
| `j` / `k`         | Focus next / previous window in the active stack |
| `[` / `]`         | Move the column divider left / right             |
| `0`               | Reset the column split                           |
| `g`               | Swap the columns                                 |
| `o`               | Move the focused window to the other stack       |
| `n` / `p`         | Focus next / previously focused desktop          |
| `1`–`9`           | Focus or create the corresponding numbered desktop |
| `u`, then `1`–`9` | Choose a numbered desktop in selection mode     |
| `w`               | Find and focus a window                          |
| `delete`          | Remove the empty current desktop                 |
| `r`               | Reflow the current screen/Space                  |

## Rewrite design

The current runtime is undergoing a POC-first selective redesign. The target contracts and replacement plan are documented in:

- [`docs/invariants.md`](docs/invariants.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/rewrite-plan.md`](docs/rewrite-plan.md)
- [`docs/performance.md`](docs/performance.md)
- [`docs/macos-settings.md`](docs/macos-settings.md)
- [`docs/pocs/`](docs/pocs/)

These documents describe the approved target, not behavior already implemented by the legacy runtime.

## Development

```sh
git clone https://github.com/caseneuve/10bucks.git
cd 10bucks
lua tests/run.lua
./scripts/install-local.sh
```

`install-local.sh` stops the loaded 10bucks instance, syncs the working-tree
Spoon to `~/.hammerspoon/Spoons/10bucks.spoon`, and reloads
Hammerspoon. It requires the Hammerspoon `hs` CLI. The same workflows are
available as `just test` and `just install` when
[just](https://github.com/casey/just) is installed.

See [the release procedure](docs/RELEASING.md) when preparing a release.
