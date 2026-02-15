#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PBXPROJ="$ROOT_DIR/PhotoTime.xcodeproj/project.pbxproj"
WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"

echo "[release-gate] checking deployment target..."
if ! rg -q 'MACOSX_DEPLOYMENT_TARGET = 14\.6;' "$PBXPROJ"; then
  echo "[release-gate] ERROR: expected MACOSX_DEPLOYMENT_TARGET = 14.6"
  exit 1
fi

echo "[release-gate] checking CI workflow jobs..."
for job in "Non-UI Tests" "Audio Regression" "UI Smoke"; do
  if ! rg -q "name: ${job}" "$WORKFLOW"; then
    echo "[release-gate] ERROR: missing CI job '${job}'"
    exit 1
  fi
done

echo "[release-gate] checking Xcode selector in CI..."
if ! rg -q 'maxim-lobanov/setup-xcode@v1' "$WORKFLOW"; then
  echo "[release-gate] ERROR: CI is missing setup-xcode action"
  exit 1
fi
if ! rg -q 'xcode-version: latest-stable' "$WORKFLOW"; then
  echo "[release-gate] ERROR: CI is not pinned to xcode-version: latest-stable"
  exit 1
fi

echo "[release-gate] running local quality gate..."
./scripts/test-ci-gate.sh

echo "[release-gate] PASSED"
