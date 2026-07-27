# Mode éditeur interne — poser des POI au doigt, manette en main

**Date** : 2026-07-27
**Statut** : validé, à implémenter
**Branche** : `plan-7a-editeur-interne`

## Problème

Ajouter un POI au contenu éditorial demande aujourd'hui d'écrire un fichier `content/poi/poi_xxx.json`
à la main, et surtout d'y inscrire une **position normalisée** — un couple `x`/`y` dans `[0,1]` sur
l'image de la carte. Cette coordonnée ne s'obtient qu'en ouvrant l'image dans un éditeur et en lisant
des pixels. C'est faisable pour dix entrées, pas pour les centaines que le sprint post-sortie exige.

Le 19 novembre 2026, personne ne sait encore où sont les collectibles de Leonida. Cette information se
produit en jouant, et le chemin entre « je découvre un spot » et « il est sur notre carte » est
aujourd'hui long de plusieurs minutes et d'un aller-retour au Mac.

Troisième constat, apparu en lisant le code du circuit communautaire : il n'existe **aucune passerelle**
entre un spot communautaire approuvé et le contenu éditorial. La foule fait le repérage, mais son
travail ne rejoint jamais `content/poi/`, donc ne compte jamais dans la progression, les collections ni
les défis.

## Prémisse

L'éditeur n'est pas un outil de rédaction : c'est un **poseur de pins au doigt**. Sa seule raison
d'être est que la coordonnée vienne de l'endroit touché plutôt que d'un calcul. Tout ce qui se rédige
mieux au clavier — titres, notes, traductions, sources, collections — reste au Mac, dans la chaîne
`content-cli` existante.

Sa fenêtre d'utilité s'ouvre le jour où l'art final de la carte Leonida existe, donc après la sortie du
jeu. Il n'a **aucune dépendance au calendrier de soumission App Store** : il vit en build debug, il ne
passe jamais par la review.

## Décisions

### D1 — Build debug, un seul utilisateur, absent du binaire soumis

L'éditeur est compilé sous `#if DEBUG`. Il n'existe pas dans le binaire App Store : rien à cacher au
reviewer, aucune surface d'attaque publique, aucun rôle serveur, aucune règle de sécurité pour un rôle
d'éditeur.

Une garantie non vérifiée n'en est pas une : la checklist de release gagne une vérification qui cherche
un marqueur de l'éditeur (`NCEditorArmedMarker`) dans le binaire Release compilé et refuse la
soumission s'il y figure.

### D2 — Leonida uniquement

L'éditeur refuse de s'armer quand la carte de référence GTA V est affichée, et le dit. Cette carte n'est
là que pour donner du volume de contenu explorable avant la sortie ; elle n'a pas vocation à recevoir
des ajouts.

Conséquence : le brouillon ne porte pas de champ « quelle carte ». La destination est toujours
`content/poi/`, jamais `content/poi-gtav/`.

### D3 — Aller-retour par Firestore, pas fichier local ni serveur local

Le téléphone écrit ses brouillons dans une collection `editor_drafts` que rien d'autre ne lit. Sur le
Mac, `content-cli pull-drafts` les matérialise en fichiers.

Deux alternatives écartées :

- **Fichier JSON exporté à la main** (Fichiers / AirDrop / iCloud Drive) : zéro backend, mais un geste
  manuel par session et une plomberie non négligeable pour faire remonter le conteneur d'une app
  jusqu'au dépôt.
- **Le téléphone écrit dans la console web du Mac par le réseau local** : le plus direct — le fichier
  apparaîtrait dans `git status` immédiatement — mais il exige le Mac allumé sur le même réseau, et
  surtout d'ouvrir la console au-delà de `127.0.0.1`, c'est-à-dire de défaire la propriété de sécurité
  documentée et testée de `tools/content-cli/ui/`.

Ce que Firestore apporte et que les deux autres n'ont pas : la **persistance hors-ligne du SDK**, sans
une ligne de code. La capture fonctionne sans réseau, la file survit à la mort de l'app, et le brouillon
quitte l'appareil dès que le réseau revient — trois heures de session ne tiennent pas sur un téléphone
qui peut crasher.

### D4 — L'identifiant est frappé au Mac, jamais sur le téléphone

Un brouillon naît avec un UUID. L'identifiant définitif `poi_*` est frappé par `pull-drafts`, une seule
fois, via la machinerie existante (`tools/basemap/gtav-poi-ids.mjs`) : clé d'identité
`editor:<collection>:<uuid>`, écrite dans `processedFrom`.

Deux bénéfices tombent de ce choix. Un titre est nécessaire pour frapper un identifiant lisible, or le
titre n'existe pas au moment de la capture. Et comme `processedFrom` porte la clé, relancer
`pull-drafts` se réapparie au fichier existant : **l'idempotence est gratuite**.

### D5 — Une règle de geste unique

**Appui long sur le vide = créer. Appui long sur un pin = agir dessus.** Le chemin fréquent est le plus
court, le chemin rare passe par un menu.

- **Créer** : appui long → grille de six catégories sous le doigt → un tap → enregistré. Aucun champ
  texte, aucune confirmation. Objectif : moins de trois secondes sans quitter le jeu des yeux. Un
  bandeau « ajouter un titre » reste quelques secondes pour les cas où on a le temps de dicter, et
  disparaît si on l'ignore.
- **Déplacer** : appui long sur un pin → menu → le pin se détache et suit le doigt, haptique à
  l'accroche et au dépôt.
- **Supprimer** : même menu, avec confirmation — seule opération destructrice.

Les pins issus de brouillons portent un contour pointillé : à tout moment on distingue ce qu'on vient de
poser de ce qui est publié et des spots communautaires.

Sur iPad, geste identique, grille en popover ancré au point touché.

### D6 — Adopter un spot communautaire

Appui long sur un pin communautaire → « Adopter » → brouillon `create` pré-rempli avec sa position et son
titre proposé, plus une référence à la contribution d'origine dans `sources`.

C'est la passerelle manquante : la foule repère, on vérifie en jeu, un tap en fait du contenu éditorial
qui compte dans la progression et les défis.

### D7 — Supprimer un POI publié écrit une pierre tombale

Un brouillon `delete` visant un POI déjà publié produit `deleted: true`, pas une suppression de fichier :
le socle embarqué ne peut pas être décompilé du binaire. Le schéma le prévoit déjà. Un `delete` visant un
POI jamais publié supprime le fichier.

### D8 — Ce qui reste au Mac, délibérément

Textes multilingues, notes, collections, `sources` éditoriales, passage en `published`. Saisir du texte
dans cinq langues au pouce pendant qu'un jeu tourne n'arrivera jamais, et le prétendre coûterait de l'UI
qui ne servirait pas.

Un brouillon sans titre est matérialisé en `status: "draft"` avec un titre généré horodaté
(`Collectible sans titre — 2026-11-20 21:42`) et `sources: ["observation directe en jeu, 2026-11-20"]`.
`publish` ne pousse que le `published` (`cli.js:130`) : un brouillon incomplet peut dormir dans le dépôt
indéfiniment sans jamais risquer la production.

## Architecture

```
NeonCompass/Core/Editor/               # tout sous #if DEBUG
  EditorDraft.swift                    # NOUVEAU — modèle: uuid, kind, category, position,
                                       #   targetPOIId?, title?, note?, sourceContributionId?, capturedAt
  EditorDraftStore.swift               # NOUVEAU — protocole (save, pending, all)
  FirestoreEditorDraftStore.swift      # NOUVEAU — écrit editor_drafts, file hors-ligne du SDK

NeonCompass/Features/Editor/           # tout sous #if DEBUG
  EditorModel.swift                    # NOUVEAU — @Observable, état d'armement + brouillons
  EditorCategoryGrid.swift             # NOUVEAU — grille six catégories, Liquid Glass
  EditorBanner.swift                   # NOUVEAU — bandeau d'état (marqueur NCEditorArmedMarker)

NeonCompass/Features/Map/
  MapScreen.swift                      # + branchement de l'éditeur sur l'appui long existant
  MapDisplayControls.swift             # + interrupteur d'armement (debug, Leonida seulement)

NeonCompass/Core/Map/
  MapScrollView.swift                  # + rendu des pins brouillons (contour pointillé),
                                       #   + geste de déplacement

tools/content-cli/
  draft-to-poi.mjs                     # NOUVEAU — fonction pure brouillon → fichier POI
  draft-to-poi.test.mjs                # NOUVEAU — node:test
  cli.js                               # + commande pull-drafts
  firestore-client.js                  # + lecture/marquage des editor_drafts
  ui/actions.mjs                       # + bouton pull-drafts

firestore.rules                        # + editor_drafts, réservé à un UID
docs/ops/…                             # + vérification du marqueur dans la checklist de release
```

**Flux** : capture → `EditorDraftStore` → `editor_drafts` (file hors-ligne) → `pull-drafts` → fichiers
`content/poi/*.json` en `status: draft` → complétion des textes → `published` → `npm run release`.

## Sécurité

- `editor_drafts` : lecture et écriture réservées à un UID unique, écrit en dur dans `firestore.rules` et
  documenté. Déploiement après `rules-diff`, comme le veut la procédure. L'UID est celui du compte Sign
  in with Apple de l'auteur, relevé au premier armement de l'éditeur (le bandeau l'affiche en debug) ;
  tant qu'il n'est pas renseigné, la règle refuse tout le monde — un défaut fermé, pas ouvert.
- Aucun chemin de contenu de l'app ne lit `editor_drafts`.
- Un brouillon ne contient aucune donnée personnelle.

## Cas limites

| Cas | Comportement |
|---|---|
| Hors-ligne | File du SDK sur disque ; le bandeau affiche le nombre en attente ; tuer l'app ne perd rien |
| Deux captures au même endroit | Rien n'est bloqué. C'est un brouillon, on le voit et on le supprime |
| `pull-drafts` relancé | Réappariement par `processedFrom`, aucun doublon |
| Fichier divergent d'un brouillon | Signalé, **rien n'est appliqué** — pas de demi-application |
| `move`/`delete` visant un POI absent du dépôt | Signalé, ignoré, brouillon marqué appliqué |
| Brouillon sans titre | Fichier `status: draft`, titre généré, impubliable en l'état |

## Constat de coût — hors périmètre, à ne pas perdre

L'éditeur lui-même ne coûte rien : un utilisateur, quelques milliers d'opérations sur toute la campagne,
très loin du quota gratuit quotidien (50 000 lectures, 20 000 écritures par jour).

En revanche, la lecture du code a mis au jour un poste de coût dominant, **dans le circuit communautaire
et non ici** : `FirestoreContributionRepository.fetchApproved()` lit tous les spots approuvés, sans
pagination ni cache, à chaque lancement de l'app. Le coût est le produit *utilisateurs × lancements ×
spots*, trois nombres qui explosent ensemble au lancement. À 50 k utilisateurs quotidiens, 3 lancements
et 3 000 spots : ~450 M lectures/jour, de l'ordre de 270 $/jour.

Le remède est déjà écrit dans le dépôt : `ContentItem` ne demande qu'un identifiant `String` et
`Codable`, donc `extension Contribution: ContentItem {}` fait entrer les spots dans `ContentStore` —
fragments, garde de version, cache SwiftData et décodage tolérant hérités tels quels. Facteur ~1 000.
Contrepartie assumée : les compteurs de votes deviennent un instantané rafraîchi périodiquement, ce que
le vote optimiste côté client masque déjà.

Chantier séparé, en tête du chemin critique release. Deux leviers de moindre rendement l'accompagnent :
la déduplication par cellule (gratuite si elle est faite avec la modération par lieu) et une alerte de
budget GCP doublée d'un coupe-circuit sur les lectures — l'interrupteur `communityContributionsEnabled`
existant ne gouverne que les écritures.

## Ce qui n'est PAS dans ce chantier

- La **modération par lieu** (regroupement des propositions communautaires à l'écriture, file par lieu,
  approbation groupée) : chantier serveur distinct, décidé mais non spécifié ici.
- La **mise en fragments des spots communautaires** : voir ci-dessus.
- L'édition de texte multilingue depuis le téléphone (D8).
- Tout rôle d'éditeur distant ou multi-utilisateur (D1).

## Tests

**JS (`node:test`)** sur `draft-to-poi.mjs`, fonction pure : frappe de l'identifiant via la clé
d'identité, double exécution idempotente, pierre tombale sur POI publié, suppression de fichier sur POI
jamais publié, conflit détecté sans application partielle, brouillon sans titre.

**Swift (Swift Testing)** avec un double en mémoire derrière `EditorDraftStore` : encodage/décodage du
brouillon, refus d'armement sur la carte de référence, adoption d'un spot communautaire en brouillon
pré-rempli, et `kind`/`targetPOIId` cohérents pour `move`/`delete`.

**Pas de test d'UI** : vérifier un appui long à la main prend trente secondes et coûte moins cher qu'un
test fragile.
