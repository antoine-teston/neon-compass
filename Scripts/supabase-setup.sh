#!/usr/bin/env bash
# Câblage du projet Supabase : clé anonyme dans le binaire, secrets du Vault et
# des Edge Functions, déploiement des fonctions.
#
# ## Une seule chose à faire avant : `supabase login`
#
# Rien à recopier. La version précédente de ce script demandait un jeton et deux
# clés en variables d'environnement, et c'était une mauvaise idée : recopier une
# clé à la main est le geste qui rate, et il rate d'une façon qui ne se voit
# qu'au premier appel réseau. Le CLI sait ouvrir une session par le navigateur et
# relire les clés du projet lui-même — autant le laisser faire.
#
# Usage :
#   supabase login                              # une fois, interactif
#   Scripts/supabase-setup.sh
#
# Optionnel, pour les notifications :
#   export APNS_KEY_ID=… APNS_TEAM_ID=… APNS_PRIVATE_KEY_PATH=AuthKey_X.p8
#   export APP_STORE_APPLE_ID=…                 # requis si APP_STORE_ENVIRONMENT=production
#
# Optionnel, pour les secrets du Vault (tâches pg_cron) :
#   export SUPABASE_DB_URL=postgresql://…       # pooler IPv4, mot de passe URL-encodé
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-quyynxabhjpzsqbblqrj}"
PROJECT_URL="https://${PROJECT_REF}.supabase.co"
BUNDLE_ID="${APP_BUNDLE_ID:-co.antoineteston.NeonCompass}"

fail() { echo "❌ $1" >&2; exit 1; }
skip() { echo "⏭  $1"; }
done_() { echo "✅ $1"; }

# Une valeur d'exemple recopiée telle quelle reste le mode d'échec le plus
# probable de tout ce qui demande un secret. Ce script n'en demande plus, mais
# les variables APNs, elles, s'écrivent encore à la main.
placeholder() {
  case "$1" in
    ''|*…*|*'...'|*xxxx*|*XXXX*|REMPLACER|'<'*'>') return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 0. Session
# ---------------------------------------------------------------------------
if ! supabase projects list --output json >/dev/null 2>&1; then
  fail "aucune session CLI. Lancer d'abord : supabase login"
fi
done_ "session CLI ouverte"

# ---------------------------------------------------------------------------
# 1. Clés du projet, relues depuis l'API
# ---------------------------------------------------------------------------
KEYS_JSON="$(supabase projects api-keys --project-ref "$PROJECT_REF" --reveal --output json)"
read_key() {
  printf '%s' "$KEYS_JSON" | python3 -c "
import json, sys
wanted = sys.argv[1]
for entry in json.load(sys.stdin):
    if entry.get('name') == wanted:
        print(entry.get('api_key') or entry.get('apiKey') or '')
        break
" "$1"
}
ANON_KEY="$(read_key anon)"
SERVICE_KEY="$(read_key service_role)"
[[ -n "$ANON_KEY" ]] || fail "clé anonyme introuvable dans la réponse de l'API — le projet $PROJECT_REF est-il bien le bon ?"
done_ "clés du projet relues (anonyme : ${ANON_KEY:0:12}…)"

# ---------------------------------------------------------------------------
# 2. Clé anonyme dans le binaire
# ---------------------------------------------------------------------------
# Publique par construction : elle est embarquée dans chaque binaire client et ne
# donne que ce que les politiques RLS autorisent. Ce qui ne doit JAMAIS atterrir
# ici, c'est `service_role`, qui les contourne.
PLIST=NeonCompass/Resources/Supabase-Info.plist
python3 - "$PLIST" "$PROJECT_URL" "$ANON_KEY" <<'PY'
import re, sys, pathlib
path, url, key = sys.argv[1:4]
p = pathlib.Path(path)
s = p.read_text()
s = re.sub(r'(<key>SUPABASE_URL</key>\s*\n\t<string>)[^<]*(</string>)', lambda m: m.group(1) + url + m.group(2), s)
s = re.sub(r'(<key>SUPABASE_ANON_KEY</key>\s*\n\t<string>)[^<]*(</string>)', lambda m: m.group(1) + key + m.group(2), s)
p.write_text(s)
PY
done_ "clé anonyme posée dans $PLIST"

# ---------------------------------------------------------------------------
# 3. Secrets du Vault, pour les tâches pg_cron
# ---------------------------------------------------------------------------
# Les trois tâches planifiées appellent les Edge Functions par HTTP et ont besoin
# de l'URL et d'une clé. Écrire ces valeurs dans une migration versionnée
# reviendrait à committer une clé `service_role` — d'où le Vault.
if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  skip "secrets du Vault : SUPABASE_DB_URL absent. Les tâches pg_cron ne pourront PAS appeler les fonctions."
elif [[ -z "$SERVICE_KEY" ]]; then
  skip "secrets du Vault : l'API n'a pas rendu de clé service_role. Idem."
elif ! command -v psql >/dev/null 2>&1; then
  skip "secrets du Vault : psql introuvable (brew install postgresql@17)."
else
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -tAc "
    select vault.create_secret('$PROJECT_URL', 'project_url')
     where not exists (select 1 from vault.secrets where name = 'project_url');
    select vault.create_secret('$SERVICE_KEY', 'service_role_key')
     where not exists (select 1 from vault.secrets where name = 'service_role_key');
  " >/dev/null
  done_ "secrets du Vault posés"
fi

# ---------------------------------------------------------------------------
# 4. Secrets des Edge Functions
# ---------------------------------------------------------------------------
supabase secrets set --project-ref "$PROJECT_REF" \
  APP_BUNDLE_ID="$BUNDLE_ID" \
  APP_STORE_ENVIRONMENT="${APP_STORE_ENVIRONMENT:-sandbox}" \
  >/dev/null
done_ "secrets App Store posés (environnement : ${APP_STORE_ENVIRONMENT:-sandbox})"

if [[ -n "${APP_STORE_APPLE_ID:-}" ]] && ! placeholder "${APP_STORE_APPLE_ID}"; then
  supabase secrets set --project-ref "$PROJECT_REF" APP_STORE_APPLE_ID="$APP_STORE_APPLE_ID" >/dev/null
  done_ "APP_STORE_APPLE_ID posé"
else
  skip "APP_STORE_APPLE_ID absent — requis UNIQUEMENT en production (la vérification de signature échoue si APP_STORE_ENVIRONMENT=production sans lui)"
fi

if [[ -n "${APNS_KEY_ID:-}" && -n "${APNS_TEAM_ID:-}" && -n "${APNS_PRIVATE_KEY_PATH:-}" ]]; then
  placeholder "$APNS_KEY_ID" && fail "APNS_KEY_ID vaut « $APNS_KEY_ID » — c'est une valeur d'exemple"
  placeholder "$APNS_TEAM_ID" && fail "APNS_TEAM_ID vaut « $APNS_TEAM_ID » — c'est une valeur d'exemple"
  [[ -f "$APNS_PRIVATE_KEY_PATH" ]] || fail "APNS_PRIVATE_KEY_PATH pointe sur un fichier absent : $APNS_PRIVATE_KEY_PATH"
  supabase secrets set --project-ref "$PROJECT_REF" \
    APNS_KEY_ID="$APNS_KEY_ID" \
    APNS_TEAM_ID="$APNS_TEAM_ID" \
    APNS_BUNDLE_ID="$BUNDLE_ID" \
    APNS_HOST="${APNS_HOST:-api.sandbox.push.apple.com}" \
    APNS_PRIVATE_KEY="$(cat "$APNS_PRIVATE_KEY_PATH")" \
    >/dev/null
  done_ "secrets APNs posés (hôte : ${APNS_HOST:-api.sandbox.push.apple.com})"
else
  skip "secrets APNs absents — send-push se déploiera mais restera muette. Sans conséquence tant que backendFeaturesEnabled vaut false."
fi

# ---------------------------------------------------------------------------
# 5. Déploiement des Edge Functions
# ---------------------------------------------------------------------------
# `app-store-notification` est la seule en --no-verify-jwt : Apple l'appelle sans
# jeton Supabase. Ce qui remplace cette vérification, c'est la signature JWS
# d'Apple, vérifiée dans la fonction AVANT toute lecture du contenu.
for fn in delete-account submit-contribution send-push rebuild-community-bundles; do
  echo "→ déploiement de $fn"
  supabase functions deploy "$fn" --project-ref "$PROJECT_REF" >/dev/null
done
echo "→ déploiement de app-store-notification (sans vérification de JWT)"
supabase functions deploy app-store-notification --project-ref "$PROJECT_REF" --no-verify-jwt >/dev/null
done_ "6 Edge Functions déployées"

echo
echo "Reste à faire à la main, non scriptable :"
echo "  · Dashboard → Authentication → Providers → Apple : activer, client ID = $BUNDLE_ID"
echo "  · App Store Connect → App Information → App Store Server Notifications :"
echo "      $PROJECT_URL/functions/v1/app-store-notification  (production ET sandbox)"
echo "  · Après la première connexion dans l'app, pour ouvrir le mode éditeur :"
echo "      insert into public.editors (uid, note) values ('<uid>', 'auteur du projet');"
