#!/usr/bin/env bash
# Vérifie que l'environnement peut builder NeonCompass. Sans effet de bord :
# diagnostique et dit quoi faire, n'installe rien de lourd lui-même.
set -euo pipefail

ok=1

if command -v xcodegen >/dev/null; then
  echo "✓ xcodegen $(xcodegen --version | tr -d 'Version: ')"
else
  echo "✗ xcodegen absent → brew install xcodegen"
  ok=0
fi

if xcodebuild -version >/dev/null 2>&1; then
  XCODE_VERSION=$(xcodebuild -version | head -1)
  echo "✓ ${XCODE_VERSION}"
  MAJOR=$(echo "${XCODE_VERSION}" | sed -E 's/Xcode ([0-9]+).*/\1/')
  if [ "${MAJOR}" -lt 26 ]; then
    echo "✗ Xcode 26+ requis (SDK iOS 26 / Liquid Glass) — installé : ${XCODE_VERSION}"
    ok=0
  fi
else
  echo "✗ Xcode inactif ou absent."
  echo "  1. Installer Xcode 26 (App Store ou developer.apple.com/download)"
  echo "  2. sudo xcode-select --switch /Applications/Xcode.app"
  echo "  3. sudo xcodebuild -license accept"
  ok=0
fi

if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS 26"; then
  echo "✓ runtime simulateur iOS 26"
else
  echo "✗ runtime simulateur iOS 26 absent → xcodebuild -downloadPlatform iOS"
  ok=0
fi

if [ "${ok}" = 1 ]; then
  echo "Environnement prêt. → Scripts/test.sh"
else
  exit 1
fi
