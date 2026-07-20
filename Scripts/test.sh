#!/usr/bin/env bash
# Génère le projet (XcodeGen) et lance tous les tests (Swift Testing).
# Usage : Scripts/test.sh [-only-testing:NeonCompassTests/Suite/test]
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
DEST=$("Scripts/simulator-destination.sh")
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass \
  -destination "${DEST}" test "$@"
