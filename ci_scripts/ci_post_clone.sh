#!/bin/sh
# Xcode Cloud runs this after checkout and before Xcode builds the project.
set -eu

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

cd "$CI_WORKSPACE"
./Scripts/generate.sh
