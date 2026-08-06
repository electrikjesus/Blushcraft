#!/usr/bin/env bash
# Extract Obtainium / store-profile stills from docs/screenshots/round-demo.mp4.
#
# Usage (from repo root):
#   ./tool/extract_store_screenshots.sh
#
# By default every still (including home) is pulled from the demo video so
# listing art stays in sync with the README GIF/MP4. Set KEEP_HOME=1 to leave
# an existing curated store/01-home.png alone.
#
# Timestamps assume the tight-paced Playwright demo. Adjust if the recording
# script changes (see tool/record_round_demo.py).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTS="${ROOT}/docs/screenshots"
STORE="${SHOTS}/store"
DEMO="${SHOTS}/round-demo.mp4"

if [[ ! -f "$DEMO" ]]; then
  echo "error: missing $DEMO — run tool/record_round_demo.py first" >&2
  exit 1
fi

mkdir -p "$STORE"

extract() {
  local t="$1" out="$2"
  ffmpeg -y -ss "$t" -i "$DEMO" -frames:v 1 -q:v 2 "$out" >/dev/null 2>&1
  echo "wrote $out @ ${t}s"
}

DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$DEMO" | cut -d. -f1)"
echo "demo duration ~${DUR}s"

# Absolute times for the trimmed ~12s release demo (tool/record_round_demo.py).
extract 1.0  "${STORE}/01-home.png"
cp -f "${STORE}/01-home.png" "${SHOTS}/home.png"

extract 4.2  "${STORE}/02-lobby.png"
extract 5.2  "${STORE}/03-play.png"
extract 6.2  "${STORE}/04-choice.png"
extract 9.0  "${STORE}/05-reveal.png"
extract 10.0 "${STORE}/06-reaction.png"
extract 11.0 "${STORE}/07-result.png"

echo "Store screenshots:"
ls -lh "${STORE}"
