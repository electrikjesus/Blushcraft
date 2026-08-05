#!/usr/bin/env bash
# Extract Obtainium / store-profile stills from docs/screenshots/round-demo.mp4
# plus an optional high-quality home capture already saved as 01-home.png.
#
# Usage (from repo root):
#   ./tool/extract_store_screenshots.sh
#
# Timestamps assume the tight-paced Playwright demo (~12s). Adjust if the
# recording script changes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTS="${ROOT}/docs/screenshots"
STORE="${SHOTS}/store"
DEMO="${SHOTS}/round-demo.mp4"

if [[ ! -f "$DEMO" ]]; then
  echo "error: missing $DEMO — record the demo first" >&2
  exit 1
fi

mkdir -p "$STORE"

extract() {
  local t="$1" out="$2"
  ffmpeg -y -ss "$t" -i "$DEMO" -frames:v 1 -q:v 2 "$out" >/dev/null 2>&1
  echo "wrote $out @ ${t}s"
}

# Prefer an existing curated home still if present.
if [[ -f "${STORE}/01-home.png" ]]; then
  echo "keeping existing ${STORE}/01-home.png"
elif [[ -f "${SHOTS}/home.png" ]]; then
  cp -f "${SHOTS}/home.png" "${STORE}/01-home.png"
  echo "copied home.png -> store/01-home.png"
else
  extract 1.0 "${STORE}/01-home.png"
fi

extract 4.0  "${STORE}/02-lobby.png"
extract 5.0  "${STORE}/03-play.png"
extract 8.5  "${STORE}/04-choice.png"
extract 9.0  "${STORE}/05-reveal.png"
extract 9.5  "${STORE}/06-reaction.png"
extract 10.5 "${STORE}/07-result.png"

echo "Store screenshots:"
ls -lh "${STORE}"
