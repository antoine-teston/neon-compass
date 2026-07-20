#!/usr/bin/env bash
# Génère le projet (XcodeGen) et builde. Usage : Scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
DEST=$("Scripts/simulator-destination.sh")
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass \
  -destination "${DEST}" build
