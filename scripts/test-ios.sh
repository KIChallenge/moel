#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOVI_DEVICE_ID="${1:?Pass an available iPhone simulator UUID from xcrun simctl list devices available}"
shift
SOVI_RUN_ID="$(date +%Y%m%d-%H%M%S)"
xcodebuild \
  -project "$PROJECT_ROOT/apps/ios/Sovi.xcodeproj" \
  -scheme Sovi \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SOVI_DEVICE_ID" \
  -derivedDataPath "$PROJECT_ROOT/artifacts/DerivedData" \
  -resultBundlePath "$PROJECT_ROOT/artifacts/TestResults/$SOVI_RUN_ID.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test "$@"
