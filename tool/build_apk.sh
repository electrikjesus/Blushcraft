#!/usr/bin/env bash
# Build a universal release APK with git-derived version codes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=git_version.sh
source "${ROOT}/tool/git_version.sh"

export PATH="${PATH}:${HOME}/flutter/bin"

echo "Building Blushcraft ${BLUSH_BUILD_NAME} (${BLUSH_BUILD_NUMBER}) @ ${BLUSH_GIT_SHA}"

flutter build apk --release \
  --build-name="${BLUSH_BUILD_NAME}" \
  --build-number="${BLUSH_BUILD_NUMBER}"

APK="${ROOT}/build/app/outputs/flutter-apk/app-release.apk"
echo "APK: ${APK}"
ls -lh "${APK}"
