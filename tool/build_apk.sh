#!/usr/bin/env bash
# Build release APKs with git-derived version codes:
#   1) universal fat APK (all ABIs)
#   2) per-ABI splits (smaller downloads for phones / emulators)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=git_version.sh
source "${ROOT}/tool/git_version.sh"

export PATH="${PATH}:${HOME}/flutter/bin"

OUT="${ROOT}/build/app/outputs/flutter-apk"
VERSION_FLAGS=(
  --build-name="${BLUSH_BUILD_NAME}"
  --build-number="${BLUSH_BUILD_NUMBER}"
)

echo "Building Blushcraft ${BLUSH_BUILD_NAME} (${BLUSH_BUILD_NUMBER}) @ ${BLUSH_GIT_SHA}"

echo "==> Universal APK (armeabi-v7a + arm64-v8a + x86_64)"
flutter build apk --release "${VERSION_FLAGS[@]}"

echo "==> Per-ABI split APKs"
flutter build apk --release --split-per-abi "${VERSION_FLAGS[@]}"

echo "APKs:"
ls -lh \
  "${OUT}/app-release.apk" \
  "${OUT}/app-armeabi-v7a-release.apk" \
  "${OUT}/app-arm64-v8a-release.apk" \
  "${OUT}/app-x86_64-release.apk"
