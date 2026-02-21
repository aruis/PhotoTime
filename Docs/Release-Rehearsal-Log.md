# Release Rehearsal Log

## 2026-02-21 (main)

- Time zone: `+0800`
- Branch: `main`
- Goal: run release gate baseline and complete one local release packaging rehearsal.

### A. Quality Gate Baseline

1. `./scripts/test-ci-gate.sh` (run at 21:18)
- Result: failed
- Duration: `real 127.29s`
- Failure: `PhotoTimeUITests-Runner ... Timed out while enabling automation mode.`
- XCResult: `.derivedData/Logs/Test/Test-PhotoTime-2026.02.21_21-19-47-+0800.xcresult`

2. Sequential timing attempts
- `./scripts/check-maintainability.sh`: passed, `real 0.01s`
- `./scripts/test-non-ui.sh`: hung (xcodebuild CPU 0), manually terminated at `real 116.71s`
- `./scripts/test-audio-regression.sh`: hung (xcodebuild CPU 0), manually terminated at `real 77.99s`
- `./scripts/test-ui-smoke.sh`: hung (xcodebuild CPU 0), manually terminated at `real 38.78s`

3. Reference successful samples (same day, earlier run)
- `test-non-ui`: passed (`IDETestOperationsObserverDebug: 45.383 elapsed`)
- `test-ui-smoke`: passed (`IDETestOperationsObserverDebug: 39.006 elapsed`)

Conclusion:
- Current machine has intermittent UI automation/test host instability.
- `test-ci-gate` baseline exists, but includes unstable noise and cannot yet be treated as a stable optimization baseline.

### B. End-to-End Packaging Rehearsal

1. Release build
- Command:
  - `xcodebuild build -project PhotoTime.xcodeproj -scheme PhotoTime -configuration Release -destination 'platform=macOS' -derivedDataPath .derivedData-release CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='-'`
- Result: passed
- Duration: `real 10.83s`

2. Package artifact
- Command:
  - `ditto -c -k --sequesterRsrc --keepParent .derivedData-release/Build/Products/Release/PhotoTime.app artifacts/PhotoTime-Release-local.zip`
- Result: passed
- Duration: `real 0.05s`
- Artifact: `artifacts/PhotoTime-Release-local.zip` (`713K`)
- SHA256: `da7e89ef0db8a98153cca6ffe5e6cde2014a5e491f07415666a219b1040e4b73`

3. Artifact verification
- `codesign --verify --deep --strict --verbose=2`: passed
- `spctl --assess --type execute -vv`: rejected (expected for ad-hoc signed local build)

### C. Blocking Issues / Next Actions

1. Blocker: local UI automation initialization/hang causes gate instability.
2. Next:
- keep release packaging path as available fallback (build + zip + checksum).
- for gate baseline, collect 3 clean samples on a stable test host/session before deciding trim targets.
