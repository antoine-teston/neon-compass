#!/usr/bin/env bash
# Vérifie qu'aucune trace du mode éditeur interne n'a fui dans un binaire Release.
#
# `#if DEBUG` protège ; ce script le prouve. Une garantie qu'on ne vérifie pas
# n'en est pas une, et celle-ci porte sur ce qu'Apple verra.
#
# Usage : Scripts/check-release-binary.sh [chemin/vers/NeonCompass.app]
# Sans argument, cherche la dernière build Release dans DerivedData.
#
# Deux pièges que ce script évite, tous deux rencontrés en l'écrivant :
#  1. En Debug, Xcode 26 place le code de l'app dans `NeonCompass.debug.dylib`
#     et laisse un binaire principal de 58 Ko quasiment vide. Chercher le
#     marqueur dans le seul binaire principal d'une build Debug ne trouve donc
#     RIEN — un succès trompeur. D'où le refus explicite des builds Debug.
#  2. Un bundle peut embarquer plusieurs Mach-O : on les balaie tous.
set -euo pipefail
cd "$(dirname "$0")/.."

MARKER="NCEditorArmedMarker"

APP="${1:-}"
if [ -z "${APP}" ]; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -name 'NeonCompass.app' -path '*Release*' -print0 2>/dev/null \
        | xargs -0 ls -dt 2>/dev/null | head -1 || true)
fi

if [ -z "${APP}" ] || [ ! -d "${APP}" ]; then
  echo "✗ aucune build Release trouvée. Builder d'abord :" >&2
  echo "  xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -configuration Release \\" >&2
  echo "    -destination \"\$(Scripts/simulator-destination.sh)\" build" >&2
  exit 2
fi

# Une build Debug ne prouverait rien : son code est ailleurs (voir l'en-tête).
if compgen -G "${APP}/*.debug.dylib" >/dev/null; then
  echo "✗ ${APP} est une build DEBUG (elle contient un .debug.dylib)." >&2
  echo "  Ce contrôle n'a de sens que sur une build Release." >&2
  exit 2
fi

BINARY="${APP}/NeonCompass"
if [ ! -f "${BINARY}" ]; then
  echo "✗ binaire introuvable : ${BINARY}" >&2
  exit 2
fi

found=0
while IFS= read -r macho; do
  if strings "${macho}" | grep -q "${MARKER}"; then
    echo "✗ marqueur ${MARKER} présent dans ${macho}"
    found=1
  fi
done < <(find "${APP}" -maxdepth 1 \( -name 'NeonCompass' -o -name '*.dylib' \) -type f)

if [ "${found}" = 1 ]; then
  echo "  L'éditeur a fui hors de #if DEBUG — NE PAS SOUMETTRE."
  exit 1
fi

echo "✓ aucun marqueur du mode éditeur dans ${APP}"
