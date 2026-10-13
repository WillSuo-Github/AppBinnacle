#!/usr/bin/env bash
# Regenerates AppBinnacle.xcodeproj from project.yml.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cd "$ROOT_DIR"
xcodegen generate --quiet --use-cache
