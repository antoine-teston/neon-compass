# Stabilité des IDs de POI & portée des défis

**Date** : 2026-07-26
**Statut** : implémenté (commits `047220b`, `b11463f`)
**Branche** : `plan-poi-id-stability`

## Problème

Deux défauts liés, tous deux invisibles aujourd'hui et irréversibles dès qu'un utilisateur aura de la progression.

**1. Les IDs de POI ne sont pas stables.** `FoundEntry` (`Core/Map/FoundEntry.swift`) et
`TrophyProgress` ne stockent qu'un identifiant de chaîne. Or `tools/basemap/gtav-poi.mjs`
frappe les IDs de deux façons, instables toutes les deux :

- `gtav-poi.mjs:173` — `poi_gtav_<slug>_<i>` où `i` est **l'index dans le tableau amont**
  (189 POI : 157 stations-service, 32 garages). Une insertion en amont décale tout ce qui suit.
- `gtav-poi.mjs:82` — `uniqueId()` suffixe `_2` en cas de collision d'ID amont, et ce suffixe
  dépend de **l'ordre d'itération**. Quatre collisions réelles chez `gta5-map` (ids 26, 30, 32, 55).

Conséquence : un ré-import qui décale l'amont réattribue silencieusement les IDs, et la
progression de chaque utilisateur pointe alors vers d'autres POI.

**2. Le dénominateur de progression est le jeu de POI courant.** `ProgressionModel.overallProgress`
(`Features/Progression/ProgressionModel.swift:65`) divise par `pois.count`. Un sync qui ajoute
trois POI fait donc régresser un utilisateur de 100 % à 96 %, widget compris. Et comme la fixture
n'est pas exhaustive (10 tracts Epsilon référencés, par exemple), on affiche « 100 % » à quelqu'un
qui n'a pas fini le jeu.

**3. Corollaire découvert en route : les « défis » n'existent pas comme entité.** L'app ne connaît
que les 6 `POICategory`. Le découpage réel du jeu vit dans le `slug` du pipeline, qui est jeté à
l'émission. « 12/50 fragments de lettre » est donc inexprimable : les 152 collectibles sont un
seul tas.

## Prémisses

- **Aucun utilisateur n'existe.** Le Plan 7 (Release / TestFlight / soumission) est devant nous.
  La fenêtre pour changer les IDs est ouverte et se refermera.
- **GTA V est figé.** Le jeu ne bougera plus ; la fixture fournit la donnée du lancement.
- **GTA VI bougera très régulièrement**, alimenté par la collecte au fil de la sortie.
- La structure des POI de GTA VI est **inconnue à ce jour**. Rien dans ce design ne doit exiger
  de la connaître.

## Décisions

### D1 — L'unité de compte d'un défi est la collection, pas la catégorie

Un champ `collection` (optionnel) sur le POI, alimenté côté V par le slug déjà calculé
(`gtav-poi.mjs:45-76`). Les 6 catégories restent ce qu'elles sont : un concept de filtrage carte
et de couleur de pin. Un POI sans `collection` est un POI de carte, hors défi — c'est le mode par
défaut, et le mode de la VI jusqu'à ce qu'on la caractérise.

Découpage réel de la fixture V après amorçage (537 POI, 15 collections) :

```
157 gas            55 wall_breach     50 spaceship_part   50 stunt_jump
 50 letter_scrap   50 under_bridge    30 nuclear_waste    28 story_vehicle
 17 garage         15 knife_flight    12 hidden_cash      10 epsilon_tract
  5 epsilon_car     5 glitch           3 vehicle_spawn
```

Les huit collections à `expectedCount` sont **complètes** dans nos données : aucune n'est en
`isDataIncomplete`. `epsilon_car` est déclarée défi sans total, son compte réel restant à vérifier —
ce qui exerce au passage le chemin « total inconnu » prévu pour la VI.

### D2 — Le dénominateur est éditorial, pas dérivé des données

Chaque collection déclare ce qu'elle attend, dans `content/collections/<id>.json` :

| `isChallenge` | `expectedCount` | Rendu | Cas |
|---|---|---|---|
| `true` | `50` | « 12 / 50 » | V, total connu |
| `true` | absent | « 37 trouvés » | VI au lancement, total inconnu |
| `false` | — | rien dans la progression | stations-service, garages |

Deux champs et non un seul, parce que « ce n'est pas un défi » et « c'est un défi dont j'ignore
le total » demandent des rendus différents. Règle de validation : `expectedCount` présent implique
`isChallenge` vrai.

Le remplissage des `expectedCount` de la V est un travail de contenu sourcé. Là où aucun total
canonique n'existe (brèches de mur, glitches, spawns de véhicules — des catalogues communautaires,
pas des collections conçues par le jeu), `isChallenge: false` est la réponse honnête plutôt qu'un
dénominateur inventé.

### D3 — Une fonction de frappe, deux façons de la persister

```
mint(identityKey) → "poi_<game>_<collection>_" + sha256(identityKey)[0..8]
```

| | Autorité de l'ID | Pourquoi |
|---|---|---|
| **GTA V** | les fichiers `content/poi-gtav/*.json` (git) | Les POI sont ré-importés ; il faut retrouver qui est qui |
| **GTA VI** | le document ID Firestore | Les POI naissent une fois via l'éditeur ; pas de ré-import |

**Invariant, valable pour les deux : on frappe une fois, on lit ensuite.** Le hash n'est jamais
recalculé sur un POI qui existe déjà. Un futur script qui re-hasherait les positions détruirait la
progression de tout le monde en silence.

### D4 — Pas de registre séparé : la fixture est son propre registre

Les 552 fichiers sont versionnés et portent tous un `processedFrom`. Le couple
`(processedFrom, id)` **est** déjà la table clé→ID, complète et commitée. Un `id-map.json` serait
une seconde copie à garder synchronisée avec la première.

Le pipeline **fusionne au lieu de régénérer** : il lit les fichiers existants, indexe par
`processedFrom`, réutilise l'ID trouvé, ne frappe que pour une clé inconnue. La purge aveugle
devient un rapport, et la suppression demande `--prune`.

La liste à purger se calcule sur les **fichiers** (un fichier dont l'id n'est pas dans le run est
périmé), pas sur les clés orphelines. Deux fichiers peuvent partager un même `processedFrom` —
c'était le cas des 4 collisions `gta5-map` suffixées `_2` par l'ancien pipeline —, auquel cas un
seul ressort comme orphelin et l'autre survivrait à la purge.

*Ce qu'on abandonne, sciemment* : un registre séparé retiendrait les clés retirées, empêchant tout
recyclage d'ID. Avec la fixture comme autorité, supprimer un fichier libère son ID. Sur un jeu figé
où la suppression est un acte humain délibéré, le risque est accepté.

### D5 — La clé d'identité n'est jamais un index

`processedFrom` devient `<source>:<collection>:<discriminant>` :

- **Sources à identifiant stable** (`danharper/GTAV`) → discriminant = `e.id` amont. Survit à une
  correction de coordonnées.
- **Sources à identifiants non uniques** (`gta5-map`, 4 collisions) → `<e.id>@<lat>,<lng>`,
  appliqué **à toute la source** dès qu'une seule collision y est détectée. Décision prise en
  scannant la source d'abord, donc indépendante de l'ordre d'itération.
- **Sources sans identifiant** (`DurtyFree`) → coordonnées **monde** arrondies au décimètre :
  `X=-1150.2,Y=-1518.4`. Monde et non normalisées : une recalibration de la projection ferait
  bouger les normalisées. Un nom amont stable, quand la source en a un, s'y **ajoute** :
  `garages.json` a besoin des deux, aucun ne suffisant seul — deux lockups distincts partagent le
  même point arrondi (`Lockup_PSY_01` et `_02` en `X=2337.6,Y=3122.5`), et deux garages distincts
  partagent le même nom (« Michael - Beverly Hills »).

`uniqueId()` est supprimé, pas réparé : deux entrées produisant la même clé **arrêtent le
pipeline**. Le suffixage silencieux est la cause racine du bug.

**Exception, découverte à l'implémentation** : deux entrées de même clé **et de contenu
strictement identique** ne sont pas une collision mais un doublon amont — `garages.json` liste
chacun de ses garages deux fois, champ pour champ. Elles sont dédupliquées (`dedupeIdenticalEntries`)
au lieu d'arrêter le run. Même clé mais contenu différent reste une erreur qui lève.

### D6 — Amorçage : re-frappe complète en IDs opaques

Le changement de format de `processedFrom` impose de toute façon un run d'amorçage qui refetch
l'amont pour convertir index → coordonnées monde. Les IDs opaques voyagent gratuitement dans ce
même commit : 537 fichiers écrits, 552 anciens purgés, `seed-poi.json` réécrit.
`poi_gtav_garage_17` devient `poi_gtav_garage_1e1251ab` — un nom qui dit visiblement « je suis
opaque, ne me recalcule pas ».

**552 → 537** : les 15 POI qui disparaissent sont les doublons amont du dump de garages, que
l'indexation par rang transformait en deux pins empilés au même pixel.

### D7 — Trophées : même invariant, aucune machinerie

Les IDs de trophées sont écrits à la main dans `content/`, pas importés. Une note dans le schéma
et la règle de revue « un ID publié ne se renomme jamais » suffisent.

### D8 — Comptage : trois règles

- **Les IDs inconnus sont ignorés.** Un `FoundEntry` dont le POI a disparu ne compte pas — sinon
  « 52 trouvés sur 50 » dès la première suppression côté VI.
- **`found` est borné par `expectedCount`.** Un jeu de données trop riche ne peut pas dépasser 100 %.
- **`mergedInto` est suivi.** `POI` gagne un `mergedInto: String?` ; au comptage, un ID fusionné est
  remappé vers sa cible. Nécessaire parce que fusionner deux doublons en supprimant l'un ferait
  perdre sa progression à tous ceux qui l'avaient coché. La **lecture** existe dès maintenant ;
  l'outillage de fusion attend le chantier éditeur.

### D9 — La progression est par jeu

`POICollection.game` reprend `MapGame` (`Core/Map/MapStyle.swift:13`). Mélanger « 12/50 fragments
GTA V » dans un anneau GTA VI n'aurait aucun sens. L'écran affiche une section par jeu ayant au
moins une collection.

Conséquence : les 6 lignes de catégorie de `ProgressionListView.swift:34` sont **remplacées** par
des lignes de défi, et `progress(in category:)` disparaît avec ses tests. Garder deux façons de
compter, c'est garantir qu'elles divergeront.

Le widget prend un seul `Double` (`NeonCompassWidgets/WidgetSummary.swift:18`) : il affiche
`leonida` dès que ce jeu a un défi à total connu, sinon `reference`.

### D10 — Le calcul est pur et mis en cache

```swift
enum ChallengeProgressCalculator {
    static func challenges(collections: [POICollection], pois: [POI], foundIDs: Set<String>) -> [ChallengeProgress]
}
```

Un balayage O(n) des POI construit `[collection: (found, referenced)]`, puis un balayage des
collections. `ProgressionModel` le stocke et le recalcule quand `(pois, foundIDs)` change.

C'est aussi un correctif de performance : aujourd'hui `overallProgress` et `progress(in:)`
refiltrent tout le tableau à chaque accès, et `ProgressionListView` les lit **7 fois par rendu**
(l'anneau + 6 catégories). Invisible à 537 POI ; avec une VI à quelques milliers de POI et une
quarantaine de collections, ce sont 7 balayages complets par rendu sur le main actor, redéclenchés
à chaque changement d'observation.

## Architecture

```
content/
  schema/collection.schema.json      # NOUVEAU
  schema/poi.schema.json             # + collection, + mergedInto
  collections/<id>.json              # NOUVEAU — 15 fichiers pour la V
  poi-gtav/*.json                    # 537 fichiers : id re-frappé, processedFrom re-clavé, + collection

tools/basemap/
  gtav-poi-ids.mjs                   # NOUVEAU — fonctions pures : clé d'identité, frappe, fusion
  gtav-poi-ids.test.mjs              # NOUVEAU — node --test
  gtav-poi.mjs                       # fusion au lieu de régénération

tools/content-cli/cli.js             # valide content/collections, + commande `bundle`

firestore.rules                      # + règle de lecture sur /collections

NeonCompass/
  Core/Map/POI.swift                 # + collection, + mergedInto, + POILoader.bundled
  Core/Map/POICollection.swift       # NOUVEAU — modèle + loader
  Core/Map/MapStyle.swift            # MapGame : Codable, valeurs brutes du contenu (gtav/leonida)
  Core/Progression/ChallengeProgress.swift  # NOUVEAU — valeur + calculateur pur
  Features/Progression/ProgressionModel.swift    # défis en cache, plus de progress(in:)
  Features/Progression/ProgressionListView.swift # lignes de défi par jeu
  Features/Progression/ProgressionScreen.swift   # compte aussi la fixture embarquée
  Resources/POI/collections.json     # NOUVEAU — projection de content/, via `cli.js bundle`
```

Le catalogue embarqué est **généré** (`node tools/content-cli/cli.js bundle`), jamais édité à la
main : `content/collections/` reste la source de vérité, exactement comme `seed-poi.json` l'est
pour les POI.

L'écran de progression ne comptait que les POI distants, alors que la carte laisse cocher les 537
POI de la fixture : quelqu'un qui en trouvait trente voyait une progression vide. Les deux jeux y
sont désormais réunis, séparés par `POICollection.game`.

`Resources/POI` est déjà une référence de dossier dans `project.yml` : aucun changement de build
n'est nécessaire pour embarquer `collections.json`.

## Tests

- `ChallengeProgressCalculatorTests` : bornage `found > expected`, `expectedCount` nil ⇒ fraction
  nil, `referenced < expected` ⇒ données incomplètes, IDs inconnus ignorés, remappage `mergedInto`,
  entrées vides, groupement par jeu.
- Régression de décodage : un POI sans `collection` ni `mergedInto` décode — c'est le format de
  tous les documents existants.
- `gtav-poi-ids.test.mjs` : dérivation de clé, détection de collision, bascule vers le discriminant
  à coordonnées, déduplication des doublons amont, insertion en tête sans déplacement des IDs
  existants, et le test qui compte — **un second run consécutif ne frappe aucun ID**.
- `LocalizationCoverageTests` apprend à lire les variantes de pluriel : les deux clés de cet ajout
  sont les premières du catalogue à en avoir, et un lookup direct de `stringUnit` les voyait comme
  non traduites.

Résultat à l'issue de l'implémentation : **151 tests Swift** et **11 tests node** au vert, build OK,
second run du pipeline à `537 réutilisés, 0 frappé, 0 orphelin`.

## Hors périmètre

- L'outillage de fusion de doublons (dépend du chantier éditeur et de données VI inexistantes).
- Le passage de `collections.json` au canal distant — chantier (a), bascule d'une ligne.
- Le filtrage de la carte par collection.
- Le chantier (a) lui-même : agrégation des lectures Firestore (aujourd'hui 1 read facturé par
  document à chaque bump de `contentVersion`). La prémisse « la VI bouge très régulièrement » le
  rend urgent, mais il est indépendant de celui-ci.
