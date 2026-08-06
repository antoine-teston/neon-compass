#!/usr/bin/env bash
# Vérifie qu'aucune trace du mode éditeur interne n'a fui dans un binaire Release.
#
# `#if DEBUG` protège ; ce script le prouve. Une garantie qu'on ne vérifie pas
# n'en est pas une, et celle-ci porte sur ce qu'Apple verra.
#
# Usage : Scripts/check-release-binary.sh [chemin/vers/NeonCompass.app]
# Sans argument, cherche la dernière build Release dans DerivedData.
#
# Trois pièges que ce script évite, tous rencontrés en le mettant à l'épreuve :
#  1. En Debug, Xcode 26 place le code de l'app dans `NeonCompass.debug.dylib`
#     et laisse un binaire principal de 58 Ko quasiment vide. Chercher le
#     marqueur dans le seul binaire principal d'une build Debug ne trouve donc
#     RIEN — un succès trompeur. D'où le refus explicite des builds Debug.
#  2. Le code de l'app n'est pas dans un seul Mach-O : l'extension widget a le
#     sien, et c'est du NÔTRE aussi. On balaie donc `PlugIns/` en plus du binaire
#     principal. Pas `Frameworks/` : nos marqueurs ne peuvent pas s'y trouver, et
#     y chercher n'ajouterait que des faux positifs venus de tiers.
#  3. **`grep -q` sous `pipefail` inverse le résultat.** Il sort au premier
#     succès et referme le tuyau ; `strings` meurt d'un SIGPIPE, et `pipefail`
#     promeut 141 en statut de pipeline. Un marqueur TROUVÉ se lisait donc
#     « absent » : 141 quand ça trouve, 1 quand ça ne trouve pas, jamais 0. Le
#     contrôle ne pouvait qu'afficher ✓, et l'a fait de sa création le 2026-07-27
#     au 2026-08-06 — vérifié en lui soumettant un vrai binaire Release où le
#     marqueur avait été délibérément mis à fuir. On consomme désormais tout le
#     flux, et `Scripts/check-release-binary-test.sh` garde la porte.
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
scanned=0
while IFS= read -r macho; do
  scanned=$((scanned + 1))
  # `grep -c` et non `grep -q` : il lit tout le flux, donc `strings` ne reçoit
  # jamais de SIGPIPE (cf. piège 3 en tête de fichier). Le `|| true` est dû à
  # `grep -c`, qui rend 1 quand le compte est zéro.
  hits=$(strings "${macho}" | grep -c -F "${MARKER}" || true)
  if [ "${hits}" -gt 0 ]; then
    echo "✗ marqueur ${MARKER} présent ${hits} fois dans ${macho}"
    found=1
  fi
# Le binaire principal, plus les exécutables des extensions sous `PlugIns/`.
# Aucun commentaire à l'intérieur du `<( )` ci-dessous : bash y apparie les
# parenthèses AVANT de reconnaître les commentaires, donc une apostrophe ou un
# backtick en commentaire y casse l'analyse — attrapé par le test le 2026-08-06.
done < <(
  find "${APP}" -maxdepth 1 \( -name 'NeonCompass' -o -name '*.dylib' \) -type f
  find "${APP}/PlugIns" -maxdepth 2 -type f -perm -u+x 2>/dev/null || true
)

# Un balayage vide rendrait « ✓ » sans avoir rien lu — le même succès trompeur
# que le piège 1, par un autre chemin.
if [ "${scanned}" = 0 ]; then
  echo "✗ aucun Mach-O balayé dans ${APP} — bundle inattendu, contrôle sans valeur." >&2
  exit 2
fi

if [ "${found}" = 1 ]; then
  echo "  L'éditeur a fui hors de #if DEBUG — NE PAS SOUMETTRE."
  exit 1
fi

echo "✓ aucun marqueur du mode éditeur — ${scanned} Mach-O balayé(s) dans ${APP}"
