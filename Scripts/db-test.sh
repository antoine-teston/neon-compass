#!/usr/bin/env bash
# Applique les migrations et fait tourner supabase/tests/schema_test.sql.
#
# Deux chemins, et le premier est le bon :
#
#   1. la pile Supabase locale (`supabase start`), qui exécute PostgREST, GoTrue
#      et Storage — donc la seule qui vérifie qu'un GRANT manquant se voit ;
#   2. un Postgres nu avec supabase/tests/_stubs.sql, quand Docker n'est pas là.
#      Utile, mais aveugle à tout ce que la pile apporte : lire l'en-tête de
#      _stubs.sql avant de s'en contenter.
#
# Usage :
#   Scripts/db-test.sh            # choisit automatiquement
#   Scripts/db-test.sh --stubs    # force le chemin sans Docker
set -euo pipefail

cd "$(dirname "$0")/.."

FORCE_STUBS=0
[[ "${1:-}" == "--stubs" ]] && FORCE_STUBS=1

if [[ $FORCE_STUBS -eq 0 ]] && docker info >/dev/null 2>&1; then
  echo "→ pile Supabase locale"
  supabase db reset
  DB_URL="$(supabase status --output json | sed -n 's/.*"DB_URL":[[:space:]]*"\([^"]*\)".*/\1/p')"
  for suite in supabase/tests/*_test.sql; do
    psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$suite"
  done
  exit 0
fi

echo "→ Postgres nu + stubs (Docker absent ou --stubs)"
command -v psql >/dev/null 2>&1 || {
  echo "psql introuvable. brew install postgresql@17, puis ajouter" >&2
  echo "  /opt/homebrew/opt/postgresql@17/bin au PATH." >&2
  exit 1
}

PGDATA_DIR="$(mktemp -d)"
SOCKET_DIR="$PGDATA_DIR/socket"
mkdir -p "$SOCKET_DIR"
cleanup() {
  pg_ctl -D "$PGDATA_DIR/data" stop >/dev/null 2>&1 || true
  rm -rf "$PGDATA_DIR"
}
trap cleanup EXIT

# Port libre plutôt qu'un port fixe : un cluster oublié d'un run précédent
# ferait échouer le démarrage avec « n'a pas pu démarrer le serveur », sans dire
# que la cause est un conflit de port.
PORT=55432
while nc -z localhost "$PORT" >/dev/null 2>&1; do PORT=$((PORT + 1)); done

initdb -D "$PGDATA_DIR/data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$PGDATA_DIR/data" -o "-p $PORT -k $SOCKET_DIR" -l "$PGDATA_DIR/pg.log" start >/dev/null || {
  echo "démarrage de Postgres impossible — journal :" >&2
  cat "$PGDATA_DIR/pg.log" >&2
  exit 1
}
until psql -h "$SOCKET_DIR" -p "$PORT" -U postgres -c 'select 1' >/dev/null 2>&1; do sleep 0.2; done

PSQL=(psql -h "$SOCKET_DIR" -p "$PORT" -U postgres -d nc -v ON_ERROR_STOP=1 -q)
psql -h "$SOCKET_DIR" -p "$PORT" -U postgres -q -c 'create database nc;'
"${PSQL[@]}" -f supabase/tests/_stubs.sql
for migration in supabase/migrations/*.sql; do
  "${PSQL[@]}" -f "$migration"
done
for suite in supabase/tests/*_test.sql; do
  "${PSQL[@]}" -f "$suite"
done
