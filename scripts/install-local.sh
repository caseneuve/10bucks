#!/usr/bin/env bash
# Install the working-tree Spoon into a running Hammerspoon instance.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_spoon="$root/10bucks.spoon"
destination_spoon="$HOME/.hammerspoon/Spoons/10bucks.spoon"

for command in hs rsync; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    if [[ "$command" == "hs" ]]; then
      echo 'Load hs.ipc in Hammerspoon and install its CLI with hs.ipc.cliInstall().' >&2
    fi
    exit 1
  fi
done

if ! hs -c 'return "10bucks-ipc-ready"' 2>/dev/null | grep -q '10bucks-ipc-ready'; then
  echo "Cannot connect to Hammerspoon through the hs CLI." >&2
  echo 'Ensure Hammerspoon is running and require("hs.ipc") is in ~/.hammerspoon/init.lua.' >&2
  exit 1
fi

echo "Stopping the loaded 10bucks instance..."
hs -c 'local s = spoon and spoon["10bucks"]; if s and s.started then s:stop() end' >/dev/null

echo "Installing $source_spoon to $destination_spoon..."
mkdir -p "$destination_spoon"
rsync -a --delete "$source_spoon/" "$destination_spoon/"
diff -qr "$source_spoon" "$destination_spoon" >/dev/null

echo "Reloading Hammerspoon..."
hs -c '_G.__tenbucksLocalInstallPending = true; hs.reload()' >/dev/null 2>&1 || true

for _ in {1..40}; do
  if hs -c '
    local s = spoon and spoon["10bucks"]
    if _G.__tenbucksLocalInstallPending == nil and s and s.started then
      return "10bucks-local-install-ready"
    end
    return "10bucks-local-install-waiting"
  ' 2>/dev/null | grep -q '10bucks-local-install-ready'; then
    echo "Installed local 10bucks and reloaded Hammerspoon."
    exit 0
  fi
  sleep 0.25
done

echo "Hammerspoon reloaded, but 10bucks did not report ready within 10 seconds." >&2
echo "Check the Hammerspoon Console for configuration errors." >&2
exit 1
