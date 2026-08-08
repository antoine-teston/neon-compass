#!/bin/sh
# Ce qu'il faut poser AVANT que la console démarre, et pourquoi chaque ligne
# existe. Tout échoue tôt et bruyamment : une console qui démarre à moitié est
# pire qu'une console qui refuse — elle laisse croire que le geste a marché.
set -eu

DEPOT=/depot

# ---------------------------------------------------------------------------
# 1. Le dépôt est-il bien là ?
#
# Sans ce contrôle, la console démarre, ne trouve aucun contenu, et affiche
# « 0 brouillon en attente » — le zéro qui se prend pour un fait, exactement ce
# que tout ce tableau de bord existe pour supprimer.
# ---------------------------------------------------------------------------
if [ ! -d "$DEPOT/.git" ]; then
  echo "le dépôt n'est pas monté sur $DEPOT — vérifier le volume de compose.yml" >&2
  exit 1
fi
if [ ! -d "$DEPOT/content" ]; then
  echo "$DEPOT est monté mais ne contient pas content/ — mauvais répertoire ?" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. « dubious ownership »
#
# Le dépôt monté appartient à l'utilisateur du Mac ; git, à l'intérieur, voit un
# propriétaire qui n'est pas le sien et refuse TOUTE commande — y compris un
# `git status`. La console rapporterait alors « git muet », ce qui enverrait
# chercher un problème de dépôt là où il n'y a qu'une question de montage.
# ---------------------------------------------------------------------------
git config --global --add safe.directory "$DEPOT"

# ---------------------------------------------------------------------------
# 3. L'identité de commit
#
# `deliver.mjs` commite. Sans identité, git refuse au moment du commit — c'est-
# à-dire après avoir créé la branche, donc dans un état à moitié fait.
# ---------------------------------------------------------------------------
if [ -n "${GIT_AUTHOR_NAME:-}" ]; then git config --global user.name "$GIT_AUTHOR_NAME"; fi
if [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then git config --global user.email "$GIT_AUTHOR_EMAIL"; fi
if ! git config --global user.email >/dev/null 2>&1; then
  echo "GIT_AUTHOR_NAME et GIT_AUTHOR_EMAIL absents — « Livrer » échouerait au commit" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Ce qui manque, DIT au démarrage plutôt que découvert au clic
#
# Aucun de ces cas n'est fatal : la console sait afficher « indisponible » et
# dire quoi faire. Mais le lire dans le journal au démarrage coûte moins cher
# que de le découvrir en cliquant sur un bouton qui refuse.
# ---------------------------------------------------------------------------
manquants=''
for v in GH_TOKEN SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  eval "valeur=\${$v:-}"
  [ -z "$valeur" ] && manquants="$manquants $v"
done
if [ -n "$manquants" ]; then
  echo "absent(s) de l'environnement :$manquants — les actions correspondantes refuseront" >&2
fi

# `gh` lit `GH_TOKEN` sans configuration : c'est ce qui remplace le trousseau
# macOS, inatteignable depuis un conteneur.
if [ -n "${GH_TOKEN:-}" ]; then
  gh auth status >/dev/null 2>&1 || echo "GH_TOKEN présent mais refusé par GitHub — jeton expiré ou portées insuffisantes (repo, workflow)" >&2
fi

exec "$@"
