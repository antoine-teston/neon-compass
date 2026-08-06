#!/usr/bin/env bash
# Éprouve `check-release-binary.sh` — dans les DEUX sens.
#
# ## Pourquoi ce test existe
#
# Le contrôle a passé un vrai binaire Release truffé du marqueur, le 2026-08-06,
# et a répondu « ✓ ». `grep -q` sous `pipefail` rendait 141 quand il trouvait :
# la condition n'a jamais pu être vraie, de la création du script le 2026-07-27
# jusqu'à ce jour-là. Personne ne l'a vu parce que **le cas nominal passe**, et
# qu'un contrôle qui ne peut qu'approuver ressemble en tout point à un contrôle
# qui approuve à raison.
#
# D'où la règle que ce fichier applique : un contrôle qui n'a jamais été vu
# ÉCHOUER n'est pas un contrôle. On lui soumet donc des bundles trafiqués.
#
# ## Pourquoi des faux bundles, et pas un build
#
# Le contrôle négatif honnête — builder Release avec le marqueur mis à fuir —
# prend plusieurs minutes et un Xcode. Celui-ci s'exécute en une seconde et
# éprouve la même chose : `strings` rend le contenu d'un fichier texte tout
# aussi bien que celui d'un Mach-O, donc un fichier texte nommé `NeonCompass`
# traverse exactement le même chemin de code.
#
# Ce qu'il ne couvre pas : que le marqueur soit VRAIMENT dans un binaire Release
# quand l'éditeur fuit. Ça, seul un vrai build le dit — c'est le travail du
# workflow `Binaire Release`, qui lance ce test puis le contrôle réel.
#
# Usage : Scripts/check-release-binary-test.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CHECK="${PWD}/Scripts/check-release-binary.sh"
MARKER="NCEditorArmedMarker"
ROOT=$(mktemp -d)
trap 'rm -rf "${ROOT}"' EXIT

failures=0

# Un bundle jetable : `NeonCompass` en fichier texte, plus ce qu'on veut autour.
make_bundle() {
  local app="${ROOT}/$1.app"
  rm -rf "${app}"
  mkdir -p "${app}"
  printf 'du contenu quelconque\nrien de suspect ici\n' > "${app}/NeonCompass"
  echo "${app}"
}

# Le statut ne suffit pas : une faute de syntaxe dans le script rend 1, comme une
# détection réussie. Deux des six cas ont d'abord « passé » ainsi. On exige donc
# aussi que la sortie dise ce qu'on attend.
expect() {
  local label=$1 wanted=$2 app=$3 needle=$4
  local output status
  output=$("${CHECK}" "${app}" 2>&1)
  status=$?
  if [ "${status}" = "${wanted}" ] && [[ ${output} == *"${needle}"* ]]; then
    printf '  ✓ %-46s (statut %s)\n' "${label}" "${status}"
    return
  fi
  if [ "${status}" != "${wanted}" ]; then
    printf '  ✗ %-46s attendu le statut %s, obtenu %s\n' "${label}" "${wanted}" "${status}"
  else
    printf '  ✗ %-46s statut %s correct, mais sortie inattendue\n' "${label}" "${status}"
    printf '      cherché : %s\n' "${needle}"
  fi
  printf '      sortie  : %s\n' "${output}"
  failures=$((failures + 1))
}

echo "check-release-binary.sh :"

# 1. Le cas nominal. Seul cas que l'ancienne version savait traiter.
app=$(make_bundle propre)
expect "bundle propre → accepté" 0 "${app}" "aucun marqueur"

# 2. LE cas qui manquait. C'est lui qui échouait silencieusement.
app=$(make_bundle fuite)
printf 'quelque chose puis %s puis autre chose\n' "${MARKER}" >> "${app}/NeonCompass"
expect "marqueur dans le binaire → refusé" 1 "${app}" "présent 1 fois"

# 3. L'extension widget porte notre code elle aussi, et l'ancienne énumération
#    ne descendait pas dans `PlugIns/`.
app=$(make_bundle extension)
mkdir -p "${app}/PlugIns/NeonCompassWidgets.appex"
printf 'widget avec %s dedans\n' "${MARKER}" > "${app}/PlugIns/NeonCompassWidgets.appex/NeonCompassWidgets"
chmod +x "${app}/PlugIns/NeonCompassWidgets.appex/NeonCompassWidgets"
expect "marqueur dans l'extension → refusé" 1 "${app}" "NeonCompassWidgets"

# 4. Un tiers dans `Frameworks/` n'est pas notre code : le refuser serait un faux
#    positif, et nous apprendrait à ignorer le contrôle.
app=$(make_bundle tiers)
mkdir -p "${app}/Frameworks/Tiers.framework"
printf 'un tiers qui contient %s\n' "${MARKER}" > "${app}/Frameworks/Tiers.framework/Tiers"
chmod +x "${app}/Frameworks/Tiers.framework/Tiers"
expect "marqueur chez un tiers → ignoré" 0 "${app}" "aucun marqueur"

# 5. Une build Debug ne prouve rien (son code est dans le .debug.dylib) : le
#    script doit refuser de se prononcer, pas approuver.
app=$(make_bundle debug)
touch "${app}/NeonCompass.debug.dylib"
expect "bundle Debug → refus de se prononcer" 2 "${app}" "build DEBUG"

# 6. Un bundle sans binaire : ne rien lire ne vaut pas « rien trouvé ».
app="${ROOT}/vide.app"
mkdir -p "${app}"
expect "bundle sans binaire → erreur" 2 "${app}" "binaire introuvable"

echo ""
if [ "${failures}" = 0 ]; then
  echo "✓ 6 cas, tous conformes"
else
  echo "✗ ${failures} cas non conforme(s)"
  exit 1
fi
