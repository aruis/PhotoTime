#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

xcodebuild test \
  -project PhotoTime.xcodeproj \
  -scheme PhotoTime \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='-' \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testPrimarySecondaryActionGroupsAndInitialButtonState \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testFailureScenarioShowsFailureCard \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testFailureRecoveryActionCanReachSuccessCard \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testSuccessScenarioShowsSuccessCard \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testInvalidScenarioShowsInlineValidation \
  -only-testing:PhotoTimeUITests/PhotoTimeUITests/testFirstRunReadyScenarioAllowsExport
