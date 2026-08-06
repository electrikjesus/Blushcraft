#!/usr/bin/env bash
# Extract Obtainium / store-profile stills from the recorded demo.
# Prefers docs/screenshots/round-demo.mp4 (local record temp); falls back to
# round-demo.gif which is what we keep in git.
#
# Usage (from repo root):
#   python3 tool/record_round_demo.py   # writes gif (+ temp mp4)
#   ./tool/extract_store_screenshots.sh
#
# Timestamps assume the tight-paced Playwright demo. Adjust if the recording
# script changes (see tool/record_round_demo.py).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTS="${ROOT}/docs/screenshots"
STORE="${SHOTS}/store"
MP4="${SHOTS}/round-demo.mp4"
GIF="${SHOTS}/round-demo.gif"

if [[ -f "$MP4" ]]; then
  DEMO="$MP4"
elif [[ -f "$GIF" ]]; then
  DEMO="$GIF"
else
  echo "error: missing $GIF (or temp $MP4) — run tool/record_round_demo.py first" >&2
  exit 1
fi

mkdir -p "$STORE"

extract() {
  local t="$1" out="$2"
  ffmpeg -y -ss "$t" -i "$DEMO" -frames:v 1 -q:v 2 "$out" >/dev/null 2>&1
  echo "wrote $out @ ${t}s"
}

DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$DEMO" | cut -d. -f1)"
echo "demo ($DEMO) duration ~${DUR}s"

# Absolute times for the trimmed ~13s release demo (tool/record_round_demo.py).
extract 1.5  "${STORE}/01-home.png"
cp -f "${STORE}/01-home.png" "${SHOTS}/home.png"

extract 4.5  "${STORE}/02-lobby.png"
extract 5.5  "${STORE}/03-play.png"
extract 7.5  "${STORE}/04-choice.png"
extract 9.7  "${STORE}/05-reveal.png"
extract 11.0 "${STORE}/06-reaction.png"
extract 12.2 "${STORE}/07-result.png"

echo "Store screenshots:"
ls -lh "${STORE}"
