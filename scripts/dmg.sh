#!/bin/bash
set -euo pipefail
app="${1:?Usage: dmg.sh app-path output.dmg}"
output="${2:?Usage: dmg.sh app-path output.dmg}"
[[ -d "$app/Contents" ]] || { echo "Missing application: $app" >&2; exit 1; }
stage="$(mktemp -d "${TMPDIR:-/tmp}/codexeyes-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Codex Eyes.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Codex Eyes" -srcfolder "$stage" -format UDZO -fs HFS+ -ov "$output"
