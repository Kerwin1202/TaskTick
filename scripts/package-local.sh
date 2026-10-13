#!/bin/bash
set -euo pipefail

# Usage: bash ./scripts/package-local.sh [version]
# Without a version, ask in a native dialog before building local release DMGs.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/.local/release-version"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [version]" >&2
  exit 1
fi

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  DEFAULT_VERSION=""
  if [ -f "$VERSION_FILE" ]; then
    DEFAULT_VERSION="$(cat "$VERSION_FILE")"
  fi
  VERSION="$(osascript - "$DEFAULT_VERSION" <<'APPLESCRIPT'
on run argv
    try
        set resultDialog to display dialog "输入版本号，例如 1.26.0" default answer (item 1 of argv) with title "打包 TaskTick" buttons {"取消", "打包"} default button "打包" cancel button "取消"
        return text returned of resultDialog
    on error number -128
        return ""
    end try
end run
APPLESCRIPT
  )"
  if [ -z "$VERSION" ]; then
    echo "已取消打包。"
    exit 0
  fi
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号格式应为三个数字段，例如 1.26.0。" >&2
  exit 1
fi

mkdir -p "$(dirname "$VERSION_FILE")"
printf '%s\n' "$VERSION" > "$VERSION_FILE"
exec bash "$SCRIPT_DIR/release.sh" "$VERSION" --local-only
