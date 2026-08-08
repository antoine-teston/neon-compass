#!/bin/sh
# Le contrôle qu'on lance après avoir démarré la console en conteneur, et à
# chaque changement de moteur Docker.
#
#   sh tools/content-cli/docker/verifier-exposition.sh [port]
#
# ─────────────────────────────────────────────────────────────────────────────
# POURQUOI IL EXISTE
#
# `compose.yml` publie sur `127.0.0.1`, et le moteur est censé l'honorer. Ce
# script ne le suppose pas : il ESSAIE d'atteindre la console depuis l'adresse
# LAN de la machine.
#
# La console n'a AUCUNE authentification. Si elle répondait depuis le réseau,
# n'importe quoi dessus — un objet connecté, un invité sur le Wi-Fi, un poste
# compromis — pourrait publier sur le CDN, pousser une branche, lancer une
# migration. Une chaîne de publication ne se protège pas par une lecture de
# fichier de configuration.
#
# ─────────────────────────────────────────────────────────────────────────────
# LA SONDE EST UNE REQUÊTE HTTP, PAS UN `nc -z`
#
# `nc -z` ne teste que la poignée de main TCP. Le proxy de Docker accepte la
# connexion avant même que le serveur soit prêt : pendant le démarrage, `nc`
# répond « ACCEPTÉE » quand `curl` n'obtient encore rien. Une première version
# de ce script s'y est laissé prendre et a affiché « ✔ tout va bien » sur une
# console qui ne servait pas. Un contrôle qui ne sait qu'approuver est
# indiscernable d'un bon résultat.
set -eu

PORT="${1:-4321}"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '')"

# Le code HTTP, ou 000 si rien n'a répondu. `--max-time` court : on cherche une
# réponse, pas à attendre un serveur lent.
sonde() {
  # `|| true` et non `|| echo 000` : curl écrit DÉJÀ `000` par `-w` quand la
  # connexion échoue. Le second l'aurait doublé — « 000000 », constaté.
  curl -s -m 4 -o /dev/null -w '%{http_code}' "http://$1:$2/api/state" 2>/dev/null || true
}

printf 'depuis ce Mac (127.0.0.1:%s)... ' "$PORT"
LOCAL="$(sonde 127.0.0.1 "$PORT")"
if [ "$LOCAL" = "000" ]; then
  echo 'aucune réponse'
  echo
  echo "✘ La console ne répond pas. Le conteneur tourne-t-il, et a-t-il fini de"
  echo "  démarrer ?   docker logs neon-console"
  exit 1
fi
echo "$LOCAL"

if [ -z "$IP" ]; then
  echo
  echo "⚠ Aucune adresse LAN (Wi-Fi coupé ?) : impossible de conclure sur"
  echo "  l'exposition réseau. Relancer une fois connecté — c'est justement là"
  echo "  que le risque existe."
  exit 2
fi

printf 'depuis le réseau local (%s:%s)... ' "$IP" "$PORT"
DISTANT="$(sonde "$IP" "$PORT")"

if [ "$DISTANT" != "000" ]; then
  echo "$DISTANT"
  echo
  echo "✘ EXPOSÉE. La console répond depuis le réseau local, et elle n'a aucune"
  echo "  authentification : elle sait publier sur le CDN et pousser des branches."
  echo
  echo "  Vérifier que compose.yml publie bien avec le préfixe :"
  echo "      - \"127.0.0.1:\${CONSOLE_PORT:-4321}:4321\""
  echo "  puis   docker-compose -f tools/content-cli/docker/compose.yml up -d --force-recreate"
  exit 1
fi
echo 'aucune réponse'

# Une connexion TCP acceptée sans réponse HTTP mérite d'être dite : quelque chose
# écoute là-bas, même si ce n'est pas la console.
if nc -z -w 3 "$IP" "$PORT" 2>/dev/null; then
  echo
  echo "⚠ Rien ne répond en HTTP, mais quelque chose ACCEPTE la connexion sur"
  echo "  $IP:$PORT. À regarder :   lsof -nP -iTCP:$PORT -sTCP:LISTEN"
  exit 1
fi

echo
echo '✔ Joignable depuis ce Mac, invisible du réseau local. C’est ce qu’on veut.'
