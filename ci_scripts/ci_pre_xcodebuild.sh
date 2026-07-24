#!/bin/sh
# The app's Debug/Release xcconfig files include Secrets.xcconfig optionally.
# CI intentionally supplies no provider secrets: deterministic tests use fixtures.
set -eu

cd "$CI_WORKSPACE"
test -f AirportXRCompanion.xcodeproj/project.pbxproj
