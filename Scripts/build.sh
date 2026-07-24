#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"

"$ROOT/Scripts/generate.sh"
if ! xcrun simctl list devices available | grep -F "$DEVICE_NAME" >/dev/null; then
  echo "Simulator '$DEVICE_NAME' is unavailable. Set SIMULATOR_NAME to an installed iPhone." >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT/AirBorder.xcodeproj" \
  -scheme AirBorder \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath "$ROOT/build/DerivedData" \
  build
