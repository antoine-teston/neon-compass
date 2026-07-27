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

Stocker la clé hors du dépôt (trousseau macOS, ou un fichier hors arborescence), puis :

```sh
export FIREBASE_SERVICE_ACCOUNT_PATH=~/.config/neoncompass/service-account.json
```

## 2. Secret GitHub Actions

Le job `publish` de `.github/workflows/content.yml` lit le secret **`FIREBASE_SERVICE_ACCOUNT`** —
le contenu JSON de la clé, pas un chemin. À ajouter dans Settings → Secrets and variables →
Actions. Sans lui, le job échoue immédiatement avec un message explicite plutôt que de partir en
erreur d'authentification obscure.

Le workflow déclare aussi l'environnement `production` : y attacher une règle de protection
(approbation requise) si tu veux qu'une publication demande une validation humaine dans l'UI
GitHub, en plus du déclenchement manuel.

## 3. Publier

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

## 4. Vérifier ce qui est en ligne

Remote Config porte `contentCommit` à côté de `contentVersion`. Comparer avec `git log` donne une
réponse vérifiable à « quel contenu est publié ? » — sans lui il faudrait comparer des documents à
la main.

## 5. Déployer les règles Firestore

`firestore.rules` a gagné `poi_gtav` et `content_bundles`. Tant que les règles actives ne les
contiennent pas, l'app lit du vide (deny-by-default) :

```sh
cd tools/content-cli && node cli.js deploy-rules
```

Le job `publish` du workflow le fait aussi, après la publication.
