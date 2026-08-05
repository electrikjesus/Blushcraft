#!/usr/bin/env bash
# Writes GitHub Release notes markdown to stdout.
# Usage: generate-release-notes.sh <tag>   e.g. v0.2.0
set -euo pipefail

TAG="${1:?Usage: generate-release-notes.sh <tag>}"
REPO="${GITHUB_REPOSITORY:-electrikjesus/Blushcraft}"
INTRO_FILE=".github/release/RELEASE_INTRO.md"
GRADLE_FILE="android/app/build.gradle.kts"

if [ ! -f "$INTRO_FILE" ]; then
  echo "::error::Missing $INTRO_FILE" >&2
  exit 1
fi

MIN_SDK="$(grep -E 'minSdk\s*=' "$GRADLE_FILE" | head -1 | grep -Eo '[0-9]+' || echo "26")"
VERSION_NAME="${TAG#v}"
if [ -f tool/git_version.sh ]; then
  # Prefer the version Flutter actually baked into this build when available.
  # shellcheck source=/dev/null
  source tool/git_version.sh
  VERSION_NAME="${BLUSH_BUILD_NAME:-$VERSION_NAME}"
fi

PREV_TAG=""
if git rev-parse "$TAG" >/dev/null 2>&1; then
  PREV_TAG="$(git tag -l 'v*' --sort=-version:refname | grep -Fxv "$TAG" | head -1 || true)"
fi

COMMIT_COUNT="$(git log --since="30 days ago" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')"
SINCE_DATE="$(date -u -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-30d '+%Y-%m-%d' 2>/dev/null || echo '30 days ago')"

CHANGELOG="$(
  git log --since="30 days ago" --pretty=format:"- %s (\`%h\`)" --no-merges 2>/dev/null \
    | sed 's/Co-authored-by: Cursor *$//' \
    | sed '/^$/d' \
    || true
)"
if [ -z "$CHANGELOG" ]; then
  CHANGELOG="- No commits in the last 30 days."
fi

RELEASE_APK="build/app/outputs/flutter-apk/app-release.apk"
DEBUG_APK="build/app/outputs/flutter-apk/app-debug.apk"
RELEASE_APK_SIZE=""
DEBUG_APK_SIZE=""
if [ -f "$RELEASE_APK" ]; then
  RELEASE_APK_SIZE="$(du -h "$RELEASE_APK" | cut -f1)"
fi
if [ -f "$DEBUG_APK" ]; then
  DEBUG_APK_SIZE="$(du -h "$DEBUG_APK" | cut -f1)"
fi

{
  echo "# Blushcraft ${TAG#v}"
  echo ""
  cat "$INTRO_FILE"
  echo ""
  echo "## What's included"
  echo ""
  echo "| File | Description |"
  echo "|------|-------------|"
  if [ -n "$RELEASE_APK_SIZE" ]; then
    echo "| **app-release.apk** (~${RELEASE_APK_SIZE}) | Signed release build. Use for installs and in-place updates. |"
  else
    echo "| **app-release.apk** | Signed release build. Use for installs and in-place updates. |"
  fi
  if [ -n "$DEBUG_APK_SIZE" ]; then
    echo "| **app-debug.apk** (~${DEBUG_APK_SIZE}) | Debug build with logging enabled. For testing only. |"
  else
    echo "| **app-debug.apk** | Debug build with logging enabled. For testing only. |"
  fi
  echo ""
  echo "### Automatic updates (Obtainium)"
  echo ""
  echo "To get notified when new \`v*\` tags ship, add this repo in [Obtainium](https://github.com/ImranR98/Obtainium):"
  echo ""
  echo "| Setting | Value |"
  echo "|---------|-------|"
  echo "| **Source** | GitHub |"
  echo "| **Repository** | \`${REPO}\` |"
  echo "| **Release filter** | \`v*\` tags |"
  echo "| **APK filter** | \`app-release.apk\` |"
  echo ""
  echo "Obtainium tracks GitHub Releases - no separate store submission. See [docs/distribution.md](https://github.com/${REPO}/blob/main/docs/distribution.md)."
  echo ""
  echo "### Build info"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| **Release tag** | \`${TAG}\` |"
  echo "| **versionName** | \`${VERSION_NAME}\` |"
  echo "| **Application ID** | \`com.blushcraft.blushcraft\` |"
  echo "| **Minimum Android** | API ${MIN_SDK}+ |"
  echo ""

  if [ -n "$PREV_TAG" ]; then
    echo "## Since ${PREV_TAG}"
    echo ""
    echo "Compare on GitHub: [${PREV_TAG}...${TAG}](https://github.com/${REPO}/compare/${PREV_TAG}...${TAG})"
    echo ""
  fi

  echo "## Changes in the last 30 days"
  echo ""
  echo "_Since ${SINCE_DATE} · ${COMMIT_COUNT} commits_"
  echo ""
  echo "$CHANGELOG"
  echo ""
  echo "---"
  echo ""
  echo "_Built from [\`${TAG}\`](https://github.com/${REPO}/releases/tag/${TAG}) · [All commits](https://github.com/${REPO}/commits/${TAG})_"
}
