#!/usr/bin/env bash
# Émet la destination xcodebuild pour le premier iPhone simulé disponible
# (le nom exact — iPhone 16/17/... — dépend du Xcode installé, on ne le fige pas).
set -euo pipefail

NAME=$(xcrun simctl list devices available | grep -oE "iPhone [A-Za-z0-9 ]+" | head -1 | sed 's/ *$//')
if [ -z "${NAME}" ]; then
  echo "Aucun simulateur iPhone disponible (runtime iOS manquant ?)" >&2
  exit 1
fi
echo "platform=iOS Simulator,name=${NAME}"
