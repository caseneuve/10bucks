#!/usr/bin/env bash
# Build the distributable Hammerspoon Spoon archive.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
output="${1:-$root/dist/10bucks.spoon.zip}"

if [[ ! "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+|-alpha\.[0-9]+)?$ ]]; then
  echo "VERSION must be YYYY.MM.DD, YYYY.MM.DD.N, or YYYY.MM.DD-alpha.N; found: $version" >&2
  exit 1
fi

if ! grep -Fqx "Tenbucks.version = \"$version\"" "$root/10bucks.spoon/init.lua"; then
  echo "10bucks.spoon/init.lua metadata must match VERSION ($version)" >&2
  exit 1
fi

if ! cmp -s "$root/LICENSE" "$root/10bucks.spoon/LICENSE"; then
  echo "10bucks.spoon/LICENSE must match the repository LICENSE" >&2
  exit 1
fi

case "$output" in
  /*) ;;
  *) output="$root/$output" ;;
esac

mkdir -p "$(dirname "$output")"
rm -f "$output"
(
  cd "$root"
  zip -q -r "$output" 10bucks.spoon -x '*/.DS_Store'
)

unzip -tq "$output" >/dev/null
archive_entries="$(unzip -Z1 "$output")"
for required_file in 10bucks.spoon/init.lua 10bucks.spoon/config.example.lua 10bucks.spoon/LICENSE; do
  if ! grep -Fxq "$required_file" <<< "$archive_entries"; then
    echo "Archive does not contain $required_file" >&2
    exit 1
  fi
done

echo "Built $output"
