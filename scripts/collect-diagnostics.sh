#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +"%Y%m%d-%H%M%S")"
OUT_BASE="${1:-$ROOT_DIR/.diagnostics}"
BUNDLE_DIR="$OUT_BASE/phototime-diagnostics-$TS"
ARCHIVE_PATH="$OUT_BASE/phototime-diagnostics-$TS.tar.gz"

APP_SUPPORT="${HOME}/Library/Application Support/PhotoTime"
LOG_DIR="$APP_SUPPORT/Logs"
STATS_FILE="$APP_SUPPORT/Diagnostics/export-failure-stats.json"

mkdir -p "$BUNDLE_DIR"

{
  echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "root_dir=$ROOT_DIR"
  echo "hostname=$(hostname)"
  echo "os=$(sw_vers -productName) $(sw_vers -productVersion)"
  echo "kernel=$(uname -a)"
  echo "xcode=$(xcodebuild -version | tr '\n' ';' | sed 's/;$/\n/')"
} >"$BUNDLE_DIR/environment.txt"

if [[ -f "$STATS_FILE" ]]; then
  cp "$STATS_FILE" "$BUNDLE_DIR/export-failure-stats.json"
else
  echo "no export failure stats file found at $STATS_FILE" >"$BUNDLE_DIR/export-failure-stats.missing.txt"
fi

if [[ -d "$LOG_DIR" ]]; then
  mkdir -p "$BUNDLE_DIR/logs"
  find "$LOG_DIR" -type f -name "*.render.log" -print0 \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 5 \
    | while IFS= read -r file; do
        cp "$file" "$BUNDLE_DIR/logs/"
      done
else
  echo "no log directory found at $LOG_DIR" >"$BUNDLE_DIR/logs.missing.txt"
fi

LATEST_LOG="$(find "$BUNDLE_DIR/logs" -type f -name "*.render.log" 2>/dev/null | head -n 1 || true)"
if [[ -n "$LATEST_LOG" ]]; then
  {
    echo "latest_log=$(basename "$LATEST_LOG")"
    echo
    echo "last_settings_lines:"
    rg -n "settings output=|layout h=|audio track:" "$LATEST_LOG" || true
  } >"$BUNDLE_DIR/config-snapshot.txt"
else
  echo "no copied render log, config snapshot unavailable" >"$BUNDLE_DIR/config-snapshot.txt"
fi

{
  echo "bundle_dir=$BUNDLE_DIR"
  echo "archive_path=$ARCHIVE_PATH"
  echo "files:"
  find "$BUNDLE_DIR" -type f | sed "s#^$BUNDLE_DIR/##" | sort
} >"$BUNDLE_DIR/manifest.txt"

mkdir -p "$OUT_BASE"
tar -czf "$ARCHIVE_PATH" -C "$OUT_BASE" "$(basename "$BUNDLE_DIR")"

echo "Diagnostics bundle created: $ARCHIVE_PATH"
