#!/usr/bin/env bash
# Stops AppBinnacle, builds it, and launches the fresh build.
# Usage: script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify]
# Set BINNACLE_DERIVED_DATA to choose where Xcode puts build products.
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AppBinnacle"
BUNDLE_ID="dev.appbinnacle.AppBinnacle"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${BINNACLE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/AppBinnacle-script}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

"$ROOT_DIR/script/generate_project.sh"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/AppBinnacle.xcodeproj" \
  -scheme AppBinnacle \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "$APP_NAME is running."
    else
      echo "$APP_NAME did not stay running." >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
