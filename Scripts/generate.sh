#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is missing. Run Scripts/bootstrap.sh first." >&2
  exit 1
fi
if [[ ! -f "$ROOT/project.yml" ]]; then
  echo "Missing project.yml at $ROOT/project.yml" >&2
  exit 1
fi

cd "$ROOT"
xcodegen generate --spec project.yml
echo "Generated AirBorder.xcodeproj from project.yml."
