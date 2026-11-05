#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

xcodebuild \
  -project "$PROJECT_ROOT/apps/ios/Sovi.xcodeproj" \
  -scheme Sovi \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PROJECT_ROOT/artifacts/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  -quiet
