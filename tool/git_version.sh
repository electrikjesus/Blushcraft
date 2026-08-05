#!/usr/bin/env bash
# Derive Flutter --build-name / --build-number from git history.
#
# versionCode (build-number): total commits on HEAD (monotonic).
# versionName (build-name):
#   - exact annotated/lightweight tag on HEAD (leading "v" stripped), or
#   - 0.1.<commit-count> when untagged.
#
# Usage:
#   source tool/git_version.sh   # sets BLUSH_BUILD_NAME, BLUSH_BUILD_NUMBER
#   tool/git_version.sh          # prints NAME and NUMBER

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not a git repository" >&2
  exit 1
fi

BLUSH_BUILD_NUMBER="$(git rev-list --count HEAD)"
SHORT_SHA="$(git rev-parse --short HEAD)"

if TAG="$(git describe --tags --exact-match HEAD 2>/dev/null)"; then
  BLUSH_BUILD_NAME="${TAG#v}"
else
  # Untagged builds: 0.1.<commits> (e.g. 0.1.12)
  BLUSH_BUILD_NAME="0.1.${BLUSH_BUILD_NUMBER}"
fi

# Dirty working tree: keep versionName Play-compatible; warn on stderr.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "warning: working tree dirty (versionName stays ${BLUSH_BUILD_NAME})" >&2
fi

export BLUSH_BUILD_NAME
export BLUSH_BUILD_NUMBER
export BLUSH_GIT_SHA="$SHORT_SHA"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "build-name=${BLUSH_BUILD_NAME}"
  echo "build-number=${BLUSH_BUILD_NUMBER}"
  echo "git-sha=${BLUSH_GIT_SHA}"
fi
