#!/bin/bash
# Builds and signs the Relic Steps Shortcut on Mike's Mac.
# Reads the Todoist token from Relic/private (do not share)/relic_config.lua,
# looks up the Relic project id, fills both into the Shortcut, signs it with
# Apple's `shortcuts sign`, and puts "Relic Steps.shortcut" in iCloud Drive.
# The token never leaves this Mac except inside the signed Shortcut.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RELIC="$(cd "$HERE/.." && pwd)"
CONFIG="$RELIC/private (do not share)/relic_config.lua"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TOKEN=$(sed -n 's/.*todoist_token *= *"\([^"]*\)".*/\1/p' "$CONFIG")
[ -n "$TOKEN" ] || { echo "No todoist_token in $CONFIG"; exit 1; }

curl -sf -H "Authorization: Bearer $TOKEN" "https://api.todoist.com/api/v1/projects?limit=200" -o "$WORK/projects.json" \
  || { echo "Todoist didn't answer. Check Wi-Fi and the token."; exit 1; }
PID=$(osascript -l JavaScript -e "
  var s = \$.NSString.stringWithContentsOfFileEncodingError('$WORK/projects.json', \$.NSUTF8StringEncoding, null).js;
  var d = JSON.parse(s); var list = d.results || d; var id = '';
  list.forEach(function (p) { if (String(p.name).toLowerCase() === 'relic') id = String(p.id); });
  id;")
[ -n "$PID" ] || { echo "No Todoist project named Relic."; exit 1; }

echo "Found the Relic project."
# `shortcuts sign` wants an XML plist whose name ends in .shortcut (same as the Cherri compiler does).
UNSIGNED="$WORK/Relic Steps_unsigned.shortcut"
sed -e "s/__TODOIST_TOKEN__/$TOKEN/" -e "s/__PROJECT_ID__/$PID/" "$HERE/relic-steps.unsigned.plist" > "$UNSIGNED"
plutil -lint "$UNSIGNED" >/dev/null
echo "Signing..."
shortcuts sign --mode anyone --input "$UNSIGNED" --output "$WORK/Relic Steps.shortcut"
[ -s "$WORK/Relic Steps.shortcut" ] || { echo "Signing produced no file."; exit 1; }

DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
cp "$WORK/Relic Steps.shortcut" "$DEST/Relic Steps.shortcut"
echo "Done. On your iPhone: Files > iCloud Drive > Relic Steps.shortcut"
