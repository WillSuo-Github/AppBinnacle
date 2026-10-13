#!/usr/bin/env bash
# Runs the unit tests. Set BINNACLE_DERIVED_DATA to choose the DerivedData folder.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${BINNACLE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/AppBinnacle-script}"

"$ROOT_DIR/script/generate_project.sh"

xcodebuild \
  -project "$ROOT_DIR/AppBinnacle.xcodeproj" \
  -scheme AppBinnacle \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  test
