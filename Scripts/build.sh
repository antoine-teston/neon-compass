#!/usr/bin/env bash
# Génère le projet (XcodeGen) et builde. Usage : Scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
DEST=$("Scripts/simulator-destination.sh")
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass \
  -destination "${DEST}" build

# NeonCompass embeds NeonCompassWidgets, so the build above already compiles it —
# but building its scheme directly too catches anything that would only break when
# the widget extension is the top-level target (e.g. a symbol only visible via the
# app's module that isn't actually shared into the widget's own sources).
xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompassWidgets \
  -destination "${DEST}" build
