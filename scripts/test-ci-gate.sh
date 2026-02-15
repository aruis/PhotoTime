#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

./scripts/test-non-ui.sh
./scripts/test-audio-regression.sh
./scripts/test-ui-smoke.sh
