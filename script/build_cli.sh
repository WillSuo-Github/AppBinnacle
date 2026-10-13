#!/usr/bin/env bash
# Builds the binnacle command-line tool and prints the path to the binary.
# Usage: script/build_cli.sh [--release]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${BINNACLE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/AppBinnacle-script}"
CONFIGURATION="Debug"
if [[ "${1:-}" == "--release" ]]; then
  CONFIGURATION="Release"
fi

"$ROOT_DIR/script/generate_project.sh"

xcodebuild \
  -project "$ROOT_DIR/AppBinnacle.xcodeproj" \
  -scheme binnacle \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build

echo "$DERIVED_DATA/Build/Products/$CONFIGURATION/binnacle"
