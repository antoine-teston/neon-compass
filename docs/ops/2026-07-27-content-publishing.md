# Publication du contenu — étapes manuelles

**Date** : 2026-07-27

Tout ce qui suit est de l'outillage ou de la configuration de console, pas du code.
La chaîne de contenu elle-même est automatisée (`content-cli release`) ; ce document couvre les
deux choses qu'un script ne peut pas faire à ta place.

## 1. Compte de service Firebase

`content-cli publish`, `release` et `deploy-rules` ont besoin d'un compte de service. Le CLI le lit
depuis `FIREBASE_SERVICE_ACCOUNT_PATH` et **jamais** depuis le dépôt.

Dans la console Firebase du projet `neoncompass-gt-vi` → Paramètres → Comptes de service →
« Générer une nouvelle clé privée ». Rôles au moindre privilège, suffisants pour ce que le CLI fait :

| Rôle | Pourquoi |
|---|---|
| Cloud Datastore User | écrire les documents et les fragments `content_bundles` |
| Firebase Remote Config Admin | incrémenter `contentVersion`, écrire `contentCommit` |
| Firebase Rules Admin | `deploy-rules` |

**Emplacement retenu** — `~/.secrets/neon-compass-firebase-admin.json`, en mode `600`, dans un
répertoire en `700`. L'export vit dans **`~/.zshenv`** et non `~/.zshrc` : zsh ne source `.zshrc` que
pour les shells *interactifs*, donc un export qui n'y serait que là resterait invisible aux scripts
et aux outils.

```sh
# ~/.zshenv
export FIREBASE_SERVICE_ACCOUNT_PATH="$HOME/.secrets/neon-compass-firebase-admin.json"
```

Le CLI, la console web et tout script lancé depuis n'importe quel shell y ont accès sans export
explicite.

## 2. Secret GitHub Actions

Le job `publish` de `.github/workflows/content.yml` lit le secret **`FIREBASE_SERVICE_ACCOUNT`** —
le contenu JSON de la clé, pas un chemin. À ajouter dans Settings → Secrets and variables →
Actions. Sans lui, le job échoue immédiatement avec un message explicite plutôt que de partir en
erreur d'authentification obscure.

Le workflow déclare aussi l'environnement `production` : y attacher une règle de protection
(approbation requise) si tu veux qu'une publication demande une validation humaine dans l'UI
GitHub, en plus du déclenchement manuel.

## 3. Console web (plutôt que les commandes)

```sh
cd tools/content-cli && npm run ui      # puis ouvrir http://127.0.0.1:4321
```

Une page locale qui expose tout le CLI en boutons, avec l'inventaire du contenu en tête (nombre
d'entrées par répertoire, publiés/brouillons, collections et leur nature) et l'état du dépôt
(branche, commit, fichiers non committés, socles à jour, credentials présents).

Sa vraie plus-value est la modération : lister les contributions en attente puis agir sur une ligne,
au lieu de recopier des identifiants dans un terminal.

**Ce qu'il faut savoir sur sa sécurité** — un serveur local qui lance des processus mérite qu'on
sache pourquoi il est inoffensif :

- Il écoute sur `127.0.0.1` uniquement, jamais `0.0.0.0`.
- Aucune donnée de requête n'atteint une ligne de commande : les actions sont une liste blanche
  d'`argv` fixes (`ui/actions.mjs`), et `spawn` est appelé sans shell. Les identifiants de modération
  sont validés contre `^[A-Za-z0-9_-]{1,128}$` et passés en élément de tableau distinct.
- Les actions qui écrivent en ligne exigent une confirmation dans le **corps** de la requête et des
  credentials présents. Un rechargement de page ou un lien partagé ne peut rien publier.

Neuf tests couvrent cette surface (`node --test ui/actions.test.mjs`), dont le refus des
identifiants hostiles et la garantie qu'aucune action `prod` n'échappe aux deux contrôles.

## 4. Publier en ligne de commande

En local, une seule commande :

```sh
cd tools/content-cli && npm run release
```

Elle enchaîne, et s'arrête à la première étape qui échoue :

1. **arbre de travail propre** — ce qui part vers Firestore doit correspondre à un commit
2. `validate` — schémas
3. `check-publishable` — règles éditoriales, marques déposées
4. `check-seeds` — les socles embarqués ne sont pas en retard sur `content/`
5. publication des documents unitaires **et** des fragments `content_bundles`
6. `contentVersion` incrémenté, `contentCommit` renseigné avec le SHA publié

`npm run release:dry` exécute les mêmes contrôles sans rien écrire (et sans exiger un arbre propre,
pour rester utilisable en pleine édition).

Depuis GitHub : Actions → « Contenu » → Run workflow → cocher « Publier réellement ».

## 5. Vérifier ce qui est en ligne

Remote Config porte `contentCommit` à côté de `contentVersion`. Comparer avec `git log` donne une
réponse vérifiable à « quel contenu est publié ? » — sans lui il faudrait comparer des documents à
la main.

## 6. Règles Firestore

**Déployées le 2026-07-27**, et le diff a révélé un écart qu'on ne soupçonnait pas : le ruleset actif
ne contenait que `poi` et `cheats`. Il manquait `guides`, `news`, `trophies`, `profiles`,
`profiles/*/progression`, `contributions`, `votes` et `reports` — donc tout ce qui a été construit des
plans 3c à 5c était en deny-by-default en production. `deploy-rules` n'avait jamais tourné depuis.

Toujours regarder avant d'écraser :

```sh
node cli.js rules-diff      # compare le ruleset actif à firestore.rules
node cli.js deploy-rules    # affiche le diff PUIS déploie
```

`deploy-rules` remplace le ruleset **d'un bloc** : une règle ajoutée directement en console Firebase
disparaîtrait sans laisser de trace. D'où le diff systématique — les lignes préfixées `-` sont celles
qu'un déploiement perdrait.

Le job `publish` du workflow déploie aussi les règles, après la publication.

## 7. État au 2026-07-27

| | État |
|---|---|
| Règles Firestore | ✅ déployées, `rules-diff` confirme l'identité avec le dépôt |
| Secret `FIREBASE_SERVICE_ACCOUNT` | ✅ posé sur le dépôt |
| Workflow « Contenu » | ✅ validé par un run réel (`check` vert, `publish` correctement sauté) |
| Environnement `production` | pas encore créé — GitHub le crée au premier run du job `publish`. Y attacher une approbation requise si tu veux un second regard humain. |
| Credentials locaux | ✅ `~/.secrets/…` en 600, répertoire en 700, export dans `~/.zshenv` |
| `workflow_dispatch` | ✅ déclenchable depuis l'UI — le workflow est sur `main` depuis la PR #30 |
| Clés de compte de service | ✅ une seule active (voir §8) |

## 8. Une seule clé de compte de service

Le compte `firebase-adminsdk-fbsvc@neoncompass-gt-vi` a porté deux paires de clés pendant un temps.
Situation résolue :

| Clé | État |
|---|---|
| `e55a3ee0…` | **active**, `~/.secrets/neon-compass-firebase-admin.json` (mode 600) et secret GitHub |
| `b52a5b59…` | **révoquée** le 2026-07-27 via `gcloud`, fichier local supprimé |

La seconde traînait dans `~/Downloads` en mode `644`, lisible par tout ce qui parcourt ce répertoire.

**Comment vérifier une révocation** — l'API IAM n'est pas activée sur le projet, et le compte de
service n'a ni le droit de l'activer ni celui de gérer les clés (c'est voulu : élargir durablement
les droits d'une clé de production pour une action ponctuelle coûterait plus que ça ne rapporte). Le
test qui marche sans rien activer est fonctionnel — une clé révoquée ne peut plus obtenir de jeton :

```js
// google-auth-library est déjà présent via firebase-admin
const auth = new GoogleAuth({ keyFile: '<chemin>', scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
await (await auth.getClient()).getAccessToken();
// clé révoquée -> invalid_grant: Invalid JWT Signature
```

Vérifié dans les deux sens au moment de la révocation : l'ancienne clé refusée, celle en usage
toujours capable d'obtenir un jeton.

## 9. Ménage de branches

`main` contient désormais tout (PR #30). Ces branches distantes n'ont plus de contenu propre — leurs
diffs à trois points contre `plan-map-reference-polish` étaient vides avant fusion :

```
plan-6c-localization  plan-ux-polish-2  plan-map-engine-rebuild
plan-map-reference-polish  plan-poi-id-stability  ops/firebase-credentials
```
