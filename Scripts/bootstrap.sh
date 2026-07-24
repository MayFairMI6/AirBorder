#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "AirBorder requires macOS and Apple's iOS toolchain." >&2
  exit 1
fi

for command_name in git swift xcodebuild xcrun; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing prerequisite: $command_name" >&2
    exit 1
  fi
done

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Select an installed Xcode command-line toolchain with xcode-select." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "XcodeGen is required. Install Homebrew, then run: brew install xcodegen" >&2
    exit 1
  fi
  brew install xcodegen
fi

"$ROOT/Scripts/generate.sh"
echo "Bootstrap complete. Configure Config/Secrets.xcconfig for live data, then run Scripts/build.sh."
