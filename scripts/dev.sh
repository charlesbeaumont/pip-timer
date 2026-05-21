#!/usr/bin/env bash
# Watch Sources/ and project.yml; on save, rebuild Debug and relaunch Pip.
#
# Usage: scripts/dev.sh
# Requires: brew install fswatch xcodegen

set -uo pipefail

command -v fswatch  >/dev/null || { echo "fswatch not found. brew install fswatch" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen" >&2; exit 1; }

cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/Pip.app"
LOG="/tmp/pip-dev-build.log"
RUNTIME_LOG="/tmp/pip-runtime.log"

rebuild() {
  printf '[%s] building...\n' "$(date +%H:%M:%S)"
  xcodegen generate >/dev/null
  if xcodebuild \
      -project Pip.xcodeproj \
      -scheme Pip \
      -configuration Debug \
      -derivedDataPath build \
      build >"$LOG" 2>&1; then
    pkill -f "$APP/Contents/MacOS/Pip" 2>/dev/null || true
    sleep 0.2
    # Launch via `open` so the app registers with LaunchServices and receives
    # NSWorkspace notifications (sleep/wake, in particular). `--stdout/--stderr`
    # still capture NSLog output to the runtime log. Running the binary
    # directly via nohup skips Cocoa app initialization and silently breaks
    # sleep/wake event delivery.
    open --stdout "$RUNTIME_LOG" --stderr "$RUNTIME_LOG" "$APP"
    printf '[%s] relaunched (runtime log: %s)\n' "$(date +%H:%M:%S)" "$RUNTIME_LOG"
  else
    printf '[%s] build failed:\n' "$(date +%H:%M:%S)"
    grep -E "error:|warning:" "$LOG" | head -20
  fi
}

rebuild

echo "watching Sources/ and project.yml..."
fswatch -o -l 0.5 Sources project.yml | while read -r _; do
  rebuild
done
