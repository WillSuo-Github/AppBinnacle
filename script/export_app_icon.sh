#!/usr/bin/env bash
# Exports App/AppIcon.icon (Icon Composer) into the legacy AppIcon.appiconset and AppIcon.icns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT_DIR/App/AppIcon.icon"
APPICONSET="$ROOT_DIR/App/Assets.xcassets/AppIcon.appiconset"
ICNS="$ROOT_DIR/App/AppIcon.icns"
ICTOOL="${ICTOOL:-$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool}"

if [[ ! -x "$ICTOOL" ]]; then
  echo "ictool not found at $ICTOOL (requires Xcode 26 or later)" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

# Legacy macOS icons keep the artwork inside the 824/1024 grid with a transparent margin.
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    inner=$(((pixels * 824 + 512) / 1024))
    if [[ $scale -eq 1 ]]; then name="icon_${size}x${size}.png"; else name="icon_${size}x${size}@2x.png"; fi
    "$ICTOOL" "$ICON" --export-image --output-file "$ICONSET/$name" \
      --platform macOS --rendition Default --width "$inner" --height "$inner" --scale 1 >/dev/null
    sips -p "$pixels" "$pixels" "$ICONSET/$name" >/dev/null
    cp "$ICONSET/$name" "$APPICONSET/$name"
  done
done

iconutil --convert icns --output "$ICNS" "$ICONSET"
echo "Exported $APPICONSET and $ICNS"
