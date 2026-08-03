#!/usr/bin/env bash
# Câblage du projet Supabase : lien CLI, clé anonyme dans le binaire, secrets du
# Vault et des Edge Functions, déploiement des fonctions.
#
# Idempotent : relançable autant de fois que nécessaire. Chaque bloc annonce ce
# qu'il fait et POURQUOI il est sauté quand il l'est — un script de mise en place
# qui saute une étape en silence est pire que pas de script du tout.
#
# Les valeurs se trouvent dans Dashboard → Settings → API (clés) et
# Account → Access Tokens (jeton personnel). Rien n'est écrit dans le dépôt sauf
# la clé ANONYME, qui est publique par construction : elle est embarquée dans
# chaque binaire client et ne donne que ce que les politiques RLS autorisent.
#
# Usage :
#   export SUPABASE_ACCESS_TOKEN=sbp_…          # requis
#   export SUPABASE_ANON_KEY=…                  # requis
#   export SUPABASE_SERVICE_ROLE_KEY=…          # requis
#   export SUPABASE_DB_URL=postgresql://…       # requis (pooler IPv4, voir plus bas)
#   export APNS_KEY_ID=… APNS_TEAM_ID=…         # optionnel, pour le push
#   export APNS_PRIVATE_KEY_PATH=AuthKey_X.p8   # optionnel
#   export APP_STORE_APPLE_ID=…                 # optionnel, requis en production
#   Scripts/supabase-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-quyynxabhjpzsqbblqrj}"
PROJECT_URL="https://${PROJECT_REF}.supabase.co"
BUNDLE_ID="${APP_BUNDLE_ID:-co.antoineteston.NeonCompass}"

fail() { echo "❌ $1" >&2; exit 1; }
skip() { echo "⏭  $1"; }
done_() { echo "✅ $1"; }

[[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]] || fail "SUPABASE_ACCESS_TOKEN manquant (Account → Access Tokens)"
[[ -n "${SUPABASE_ANON_KEY:-}" ]] || fail "SUPABASE_ANON_KEY manquant (Settings → API)"

# ---------------------------------------------------------------------------
# 1. Lien du CLI
# ---------------------------------------------------------------------------
echo "→ lien du CLI sur $PROJECT_REF"
supabase link --project-ref "$PROJECT_REF" >/dev/null
done_ "CLI lié"

# ---------------------------------------------------------------------------
# 2. Clé anonyme dans le binaire
# ---------------------------------------------------------------------------
# Publique par construction. Ce qui ne doit JAMAIS atterrir ici, c'est
# `service_role`, qui contourne RLS.
PLIST=NeonCompass/Resources/Supabase-Info.plist
python3 - "$PLIST" "$PROJECT_URL" "$SUPABASE_ANON_KEY" <<'PY'
import re, sys, pathlib
path, url, key = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
s = p.read_text()
s = re.sub(r'(<key>SUPABASE_URL</key>\s*\n\t<string>)[^<]*(</string>)', rf'\g<1>{url}\g<2>', s)
s = re.sub(r'(<key>SUPABASE_ANON_KEY</key>\s*\n\t<string>)[^<]*(</string>)', rf'\g<1>{key}\g<2>', s)
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
  skip "secrets du Vault : SUPABASE_DB_URL manquant. Les tâches pg_cron ne pourront PAS appeler les fonctions."
elif [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  skip "secrets du Vault : SUPABASE_SERVICE_ROLE_KEY manquant. Idem."
else
  command -v psql >/dev/null || fail "psql introuvable (brew install postgresql@17)"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -tAc "
    select vault.create_secret('$PROJECT_URL', 'project_url')
     where not exists (select 1 from vault.secrets where name = 'project_url');
    select vault.create_secret('$SUPABASE_SERVICE_ROLE_KEY', 'service_role_key')
     where not exists (select 1 from vault.secrets where name = 'service_role_key');
  " >/dev/null
  done_ "secrets du Vault posés (project_url, service_role_key)"
fi

# ---------------------------------------------------------------------------
# 4. Secrets des Edge Functions
# ---------------------------------------------------------------------------
supabase secrets set \
  APP_BUNDLE_ID="$BUNDLE_ID" \
  APP_STORE_ENVIRONMENT="${APP_STORE_ENVIRONMENT:-sandbox}" \
  >/dev/null
done_ "secrets App Store posés (environnement : ${APP_STORE_ENVIRONMENT:-sandbox})"

if [[ -n "${APP_STORE_APPLE_ID:-}" ]]; then
  supabase secrets set APP_STORE_APPLE_ID="$APP_STORE_APPLE_ID" >/dev/null
  done_ "APP_STORE_APPLE_ID posé"
else
  skip "APP_STORE_APPLE_ID absent — requis UNIQUEMENT en production (la vérification de signature échouera si APP_STORE_ENVIRONMENT=production sans lui)"
fi

if [[ -n "${APNS_KEY_ID:-}" && -n "${APNS_TEAM_ID:-}" && -n "${APNS_PRIVATE_KEY_PATH:-}" ]]; then
  [[ -f "$APNS_PRIVATE_KEY_PATH" ]] || fail "APNS_PRIVATE_KEY_PATH pointe sur un fichier absent : $APNS_PRIVATE_KEY_PATH"
  supabase secrets set \
    APNS_KEY_ID="$APNS_KEY_ID" \
    APNS_TEAM_ID="$APNS_TEAM_ID" \
    APNS_BUNDLE_ID="$BUNDLE_ID" \
    APNS_HOST="${APNS_HOST:-api.sandbox.push.apple.com}" \
    APNS_PRIVATE_KEY="$(cat "$APNS_PRIVATE_KEY_PATH")" \
    >/dev/null
  done_ "secrets APNs posés (hôte : ${APNS_HOST:-api.sandbox.push.apple.com})"
else
  skip "secrets APNs absents — send-push se déploiera mais échouera à l'envoi. Sans conséquence tant que backendFeaturesEnabled vaut false."
fi

# ---------------------------------------------------------------------------
# 5. Déploiement des Edge Functions
# ---------------------------------------------------------------------------
# `app-store-notification` est la seule en --no-verify-jwt : Apple l'appelle sans
# jeton Supabase. Ce qui remplace cette vérification, c'est la signature JWS
# d'Apple, vérifiée dans la fonction avant toute lecture du contenu.
for fn in delete-account regenerate-handle submit-contribution send-push rebuild-community-bundles; do
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
