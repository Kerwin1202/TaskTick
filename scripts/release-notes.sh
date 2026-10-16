#!/bin/bash
set -euo pipefail

# Usage: bash scripts/release-notes.sh <tag> <commit> <owner/repo>
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <tag> <commit> <owner/repo>" >&2
  exit 1
fi

TAG="$1"
BUILD_COMMIT=$(git rev-parse --verify "${2}^{commit}")
REPO="$3"

# Find the preceding version on the release branch, excluding this tag.
# The commit list below still includes all merged commits.
PREVIOUS_TAG=$(git describe --tags --first-parent --abbrev=0 \
  --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude "$TAG" \
  "$BUILD_COMMIT" 2>/dev/null || true)

printf '版本：`%s`\n\n' "$TAG"

# Lightweight tags point to commits and have no tag message of their own.
if [ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null || true)" = tag ]; then
  TAG_MESSAGE=$(git for-each-ref \
    --format='%(contents:subject)%0a%0a%(contents:body)' "refs/tags/$TAG")
  if [ -n "$TAG_MESSAGE" ]; then
    printf '## 版本说明\n\n%s\n\n' "$TAG_MESSAGE"
  fi
fi

printf '## 提交记录\n\n'
if [ -n "$PREVIOUS_TAG" ]; then
  COMMIT_RANGE="${PREVIOUS_TAG}..${BUILD_COMMIT}"
  printf '提交范围：`%s` → `%s`\n\n' "$PREVIOUS_TAG" "$TAG"
else
  COMMIT_RANGE="$BUILD_COMMIT"
  printf '首次发布，包含此版本的全部历史提交。\n\n'
fi

COMMITS=$(git log --reverse --topo-order \
  --format="- %s ([%h](https://github.com/${REPO}/commit/%H)) — %an" \
  "$COMMIT_RANGE")
if [ -n "$COMMITS" ]; then
  printf '%s\n' "$COMMITS"
else
  printf '两个版本之间没有新的提交。\n'
fi

if [ -n "$PREVIOUS_TAG" ]; then
  printf '\n[完整变更](https://github.com/%s/compare/%s...%s)\n' "$REPO" "$PREVIOUS_TAG" "$TAG"
fi
printf '\n源码提交：[%s](https://github.com/%s/commit/%s)\n' "$BUILD_COMMIT" "$REPO" "$BUILD_COMMIT"
