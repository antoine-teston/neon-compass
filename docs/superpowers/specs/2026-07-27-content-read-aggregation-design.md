# Agrégation des lectures de contenu & overlay distant

**Date** : 2026-07-27
**Statut** : implémenté
**Branche** : `plan-poi-id-stability`

## Problème

`FirestoreContentRepository.fetchAll()` faisait un `getDocuments()` sur la collection entière.
**Firestore facture une lecture par document.** À chaque bump de `contentVersion`, chaque client
relisait donc autant de documents qu'il y a d'entrées — le « delta » du nom n'était qu'un portillon
de version, jamais un delta par document.

À 20 k DAU et ~1 500 POI publiés, un bump coûtait 30 M lectures ≈ 17 €. Pendant le sprint de
sortie, avec un bump par jour, ~500 €/mois sur le seul POI — le budget de la spec est à moins de
100 €/mois tout compris.

Second défaut, indépendant : le socle embarqué (`seed-poi.json`, `collections.json`) est figé dans
le binaire. Corriger une position fausse imposait une soumission App Store, soit deux à sept jours
pour déplacer un pin.

## Prémisse

GTA VI **bougera très régulièrement** au fil de la collecte de données. C'est ce qui transforme le
coût de lecture d'un inconfort théorique en poste dominant : le modèle tient à un bump par mois,
pas à un bump par jour.

## Décisions

### D1 — Agrégats chunkés dans Firestore, pas un CDN

Une collection publiée devient des documents `content_bundles/{collection}_{chunk}` portant
`{ collection, chunk, items[] }`, 500 entrées par fragment. Un client lit ⌈N/500⌉ documents : trois
au lieu de mille cinq cents.

**Correction assumée d'une recommandation antérieure.** L'option privilégiée au départ était un JSON
sur Firebase Hosting (0 lecture Firestore, cache CDN, pas de plafond de taille). Deux faits l'ont
écartée :

1. Hosting **n'est pas provisionné** (`firebase.json` ne déclare que firestore, functions et les
   émulateurs), et le provisionner demande une action d'infra hors de ce chantier.
2. Une fois les agrégats **chunkés**, ses deux avantages s'évaporent. Le plafond de 1 MiB par
   document — atteignable vers 1 300 entrées à cinq langues remplies — ne s'applique plus au
   tableau. Et le gain de coût devient dérisoire : 20 k DAU × 3 lectures × 30 bumps ≈ 1 €/mois.

La lecture reste derrière `ContentRemoteRepository`, donc basculer vers Hosting resterait un fichier
à changer si les chiffres l'exigeaient un jour.

Les documents unitaires **continuent d'exister** dans Firestore : ils sont la surface d'écriture du
mode éditeur et ce qu'on inspecte en console. Ce n'est simplement plus ce que l'app lit. Le coût
d'écriture supplémentaire est négligeable (1 500 écritures ≈ 0,003 $).

### D2 — Socle embarqué + overlay distant, fusionnés par identifiant

`ContentStore` prend un `seed:` et fusionne : le socle est la base, l'overlay écrase à identifiant
égal, et une **pierre tombale** (`deleted: true`) retire — seul moyen d'annuler une entrée qu'on ne
peut pas décompiler du binaire.

Bénéfice concret : une position GTA V fausse se corrige en publiant un document, sans passer par
l'App Store.

**Le cache porte l'overlay, pas le résultat fusionné.** Sinon une mise à jour de l'app livrant un
socle enrichi serait masquée par un cache écrit à l'époque de l'ancien socle, jusqu'au prochain bump
de version. Un test fige ce comportement.

L'ordre du socle est préservé, puis les ajouts : l'affichage ne se réordonne pas à chaque sync.

### D3 — Deux collections Firestore pour les POI, pas une

`content/poi/` → `poi` (volet à venir) et `content/poi-gtav/` → `poi_gtav` (carte de référence).

La séparation est déjà celle du dépôt, et elle est délibérée côté app : les positions de la fixture
sont normalisées **sur la carte de référence**, donc les mêler au contenu du jeu à venir poserait des
centaines de pins à des endroits qui ne veulent rien dire — cf.
`MapModel.pois(for:remote:reference:)`, qui n'a volontairement aucun repli de l'un vers l'autre.

Conséquence : `MapScreen` et `ProgressionScreen` portent deux stores de POI, l'un avec socle, l'autre
sans.

### D4 — Les pierres tombales n'existent que là où il y a un socle

`POI` et `POICollection` portent un `deleted`. Les collections purement distantes (cheats, guides,
actu, trophées) n'en ont pas besoin : leur bundle est reconstruit intégralement à chaque publication,
donc ne plus publier un document suffit à le faire disparaître. Le protocole `ContentItem` fournit
`isDeleted == false` par défaut, et seuls les deux types à socle le surchargent.

### D5 — Le catalogue de collections rejoint le canal distant

`collections` a désormais son store avec le JSON embarqué comme socle. Une collection GTA VI pourra
donc être déclarée — avec son `expectedCount` — sans mise à jour de l'app, le jour où on saura ce
que ses POI sont.

## Correctif au passage

`pushDocuments` écrivait tout dans **un seul batch Firestore**, plafonné à 500 opérations. La fixture
GTA V en compte 537 : un `publish` aurait échoué d'un bloc. Les écritures sont désormais découpées.

## Architecture

```
NeonCompass/Core/Content/
  ContentItem.swift                  # NOUVEAU — identité + isDeleted, conformances
  ContentMerge.swift                 # NOUVEAU — fusion pure socle/overlay
  ContentBundle.swift                # NOUVEAU — format de fragment, chunkSize
  ChunkedContentRepository.swift     # NOUVEAU — lit content_bundles
  ContentStore.swift                 # + seed, fusionne, cache l'overlay
  FirestoreContentRepository.swift   # conservé, plus utilisé par l'app

tools/content-cli/
  cli.js                             # KINDS porte schéma + collection cible ; poi-gtav ajouté
  firestore-client.js                # pushBundles, écritures découpées à 500

firestore.rules                      # + poi_gtav, + content_bundles
content/schema/{poi,collection}.schema.json   # + deleted
```

## Ce qui n'est PAS fait

Les 537 POI de la fixture restent en `status: "draft"`, donc rien ne part vers Firestore
aujourd'hui : le socle embarqué couvre l'app, et la mécanique d'overlay s'active dès qu'on publie
quoi que ce soit. Basculer ces 537 entrées en `published` est une décision de contenu, pas une
décision technique.

## Tests

- `ContentMergeTests` (11 cas) : overlay écrase, ajoute, pierre tombale retire, pierre tombale
  orpheline ignorée, ordre du socle préservé, identifiant dupliqué arbitré, fusion générique sur
  `POICollection`.
- `ContentStoreTests` (+4) : socle exposé avant tout sync, sync patche au lieu de remplacer, **le
  cache porte l'overlay** (un socle enrichi après mise à jour de l'app est bien vu), pierre tombale
  distante.
- `ContentBundleTests` : le format écrit par le CLI se décode, fragment vide, et `chunkSize` figé à
  500 — la valeur est dupliquée entre les deux côtés, donc la dérive doit se voir.

168 tests Swift au vert, build OK, `validate`/`check-publishable` à 559/559.
