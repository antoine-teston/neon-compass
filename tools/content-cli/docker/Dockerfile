# La console de pilotage, en conteneur.
#
# ─────────────────────────────────────────────────────────────────────────────
# CE CONTENEUR N'EST PAS CELUI DU MONITEUR, ET L'OPPOSÉ SUR CHAQUE POINT
#
# `tools/monitor/` embarque cinq fichiers, aucune dépendance, ni git ni gh, et
# écoute sur toutes les interfaces — il est sûr PARCE QU'IL N'Y A RIEN À
# APPELER.
#
# Celui-ci fait l'inverse : il embarque `git` et `gh`, monte le dépôt en
# écriture, détient un jeton GitHub et la clé `service_role`. Il peut publier
# sur le CDN, pousser une branche et lancer une migration.
#
# Il n'est donc défendable QUE parce qu'il écoute sur 127.0.0.1 — et ce point
# est vérifié par un test (`docker.test.mjs`), pas laissé à la vigilance. Faire
# passer ce port à `0.0.0.0` mettrait sur le réseau local un service sans
# authentification qui sait publier en production.
#
# ─────────────────────────────────────────────────────────────────────────────
# CE QUE LE CONTENEUR COÛTE, ET QU'IL FAUT SAVOIR AVANT DE LE LANCER
#
#   1. **Le trousseau.** Sur le Mac, `gh` s'authentifie par le trousseau macOS.
#      Un conteneur ne l'atteint pas : le jeton doit sortir dans un `.env`. Un
#      secret dans un fichier est moins bien gardé qu'un secret dans le
#      trousseau — c'est le prix, il est réel, et il se limite en donnant au
#      jeton les seules portées `repo` et `workflow`.
#   2. **L'arbre partagé.** Le dépôt est monté en écriture : le conteneur voit
#      la branche sur laquelle VOUS êtes, et écrit dedans. Changer de branche
#      pendant qu'il tourne change ce qu'il voit, sans qu'il le sache.
#
# Debian et non Alpine : `gh` y a un dépôt apt officiel, et `git` y est celui
# que tout le monde teste. Une image de 200 Mo qu'on lance une fois n'est pas
# un problème ; un `gh` compilé à la main pour arm64 en serait un.
FROM node:22.14-bookworm-slim

# `gh` par son dépôt officiel — la clé est vérifiée, pas récupérée en aveugle.
# `git` et `ca-certificates` viennent avec.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && apt-get purge -y gnupg \
 && rm -rf /var/lib/apt/lists/*

# Le dépôt est MONTÉ, pas copié : la console édite `content/` et commite. Une
# copie dans l'image serait figée à la construction, et ses écritures
# disparaîtraient au redémarrage.
WORKDIR /depot/tools/content-cli

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Un HOME ÉCRIVABLE, et c'est indispensable : le conteneur tourne sous l'uid du
# Mac (501), qui n'existe pas dans l'image et n'a donc pas de répertoire
# personnel. `git config --global` tentait d'écrire `//.gitconfig`, échouait, et
# l'entrée sortait — conteneur en boucle de redémarrage, avec pour seule trace
# un « Permission denied » qui ne nomme pas la cause.
ENV HOME=/tmp/console-home
ENV NODE_ENV=production
EXPOSE 4321

# La sonde interroge le PROCESSUS, pas Supabase ni GitHub : un redémarrage en
# boucle parce que le réseau est tombé remplacerait une console qui dit
# « injoignable » par une console qui ne dit plus rien.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4321/api/state').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["node", "ui/server.mjs"]
