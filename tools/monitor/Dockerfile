# Le moniteur, pour un Raspberry Pi.
#
# ─────────────────────────────────────────────────────────────────────────────
# CE QUI N'ENTRE PAS DANS CETTE IMAGE, ET C'EST L'ESSENTIEL
#
#   - pas de `git`, pas de `gh`, pas de CLI Supabase ;
#   - pas le dépôt : quatre fichiers, listés un par un ci-dessous ;
#   - pas `tools/content-cli/`, qui sait publier ;
#   - aucune dépendance npm : `metrics.mjs` n'utilise que `fetch` et
#     `node:http`, donc il n'y a pas de `npm install`, pas de `node_modules`,
#     et rien à auditer côté chaîne d'approvisionnement.
#
# Ce n'est pas de l'hygiène : ce service écoute sur le réseau local, sans
# authentification. La seule chose qui le rend sûr est qu'il N'Y A RIEN à
# appeler. Une image « au cas où » avec git dedans annulerait tout le raisonnement.
#
# ─────────────────────────────────────────────────────────────────────────────
# CONSTRUIRE
#
#   Depuis un Mac Apple Silicon vers un Pi 64 bits, c'est la MÊME architecture
#   (arm64) — il n'y a donc rien à émuler :
#
#     docker build -t neon-moniteur tools/monitor
#
#   Pour un Pi 32 bits (Pi Zero, Pi 3 en Raspberry Pi OS 32 bits), il faut
#   croiser explicitement, et c'est lent :
#
#     docker buildx build --platform linux/arm/v7 -t neon-moniteur tools/monitor
#
# Épinglé sur une version mineure et non sur `node:22-alpine` tout court : un
# `latest` implicite fait qu'une reconstruction six mois plus tard ne produit
# pas la même image, et le jour où elle casse on cherche dans son propre code.
FROM node:22.14-alpine

# `node` (uid 1000) existe déjà dans l'image officielle. On ne crée rien, on
# cesse simplement d'être root.
WORKDIR /app

# Fichier par fichier, jamais `COPY . .` : la liste EST la garantie. Un
# `COPY . .` embarquerait tout ce que quelqu'un déposerait un jour dans ce
# dossier, y compris un `.env`.
COPY --chown=node:node metrics.mjs graphes.mjs graphes.css index.html server.mjs ./

USER node

ENV NODE_ENV=production \
    PORT=4322 \
    HOST=0.0.0.0

EXPOSE 4322

# La sonde interroge le processus, pas Supabase — voir `/sante` dans server.mjs.
# Un conteneur qui redémarrerait en boucle parce que le réseau est tombé
# remplacerait un tableau de bord qui dit « injoignable » par un écran noir.
HEALTHCHECK --interval=30s --timeout=4s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/sante').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.mjs"]
