#!/bin/bash
# Shared host-side configuration; sourced by the executable helpers.
VM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TART_BIN="${TART_BIN:-$HOME/.tart/tool/tart.app/Contents/MacOS/tart}"
TENBUCKS_VM="${TENBUCKS_VM:-10bucks-lab}"
VM_SSH_KEY="${VM_SSH_KEY:-$HOME/.tart/keys/10bucks_ed25519}"
VM_KNOWN_HOSTS="${VM_KNOWN_HOSTS:-$HOME/.tart/known_hosts}"
[[ -x "$TART_BIN" ]] || { echo "Tart executable not found: $TART_BIN (set TART_BIN)" >&2; exit 1; }
