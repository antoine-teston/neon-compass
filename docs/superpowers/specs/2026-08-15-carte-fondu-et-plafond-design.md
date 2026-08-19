# Fondu des bords de carte, et plafond de zoom par appareil

**Date :** 2026-08-15
**Branche :** `feat/carte-fondu-plafond`, empilée sur `feat/carte-pavage-z6-plat` (PR #114)
**Statut :** validé en séance

## Le problème, mesuré

Deux défauts distincts, tous deux constatés sur iPad Pro 13 (M5), tous deux nés du chantier précédent.

### 1. Le plafond de zoom est une constante là où c'est une géométrie

`MapScrollView.setArt` pose `maximumZoomScale = tileManifest == nil ? 2.5 : 3.3`.

Or ce qu'il y a à voir dépend de l'appareil. Le niveau le plus fin de la pyramide fait 18 432 px pour 2 048 pt de contenu, soit **9,0 px source par point de contenu** ; l'écran, lui, en rend `zoom × displayScale`. Le zoom du 1:1 vaut donc `9,0 / displayScale` : **3,0 sur un appareil ×3, 4,5 sur un ×2**.

Conséquence chiffrée du plafond unique de 3,3 :

| appareil | agrandissement réclamé au plafond |
|---|---|
| iPhone 17 (×3) | 1,10× — au-delà du 1:1, c'est le réglage voulu |
| iPad Pro 13 (×2) | **0,73×** |

Sur iPad on s'arrête donc **avant** d'avoir montré les pixels qu'on embarque : au plafond, l'écran n'affiche que 73 % de la finesse linéaire livrée. C'est exactement l'erreur que le seuil d'engagement des tuiles avait déjà enseignée — un nombre qui dépend de l'écran, écrit comme s'il n'en dépendait pas (voir `tools/basemap/SOURCES.md`, « Le seuil d'engagement n'est pas une constante »).

Vérifié à l'écran : au même grossissement, une capture prise à 4,5 est nettement plus nette qu'une capture prise à 3,3 puis agrandie — libellés de rue et micro-codes lisibles d'un côté, empâtés de l'autre. Une capture à 4,95 est indiscernable de celle à 4,5.

### 2. Le bord de la carte est une découpe franche sur du noir

Depuis que le débord vaut une demi-fenêtre au-delà du repos — ce qui permet d'amener une épingle côtière au centre, et qui est un acquis à conserver —, on peut pousser la carte jusqu'à ce que son coin tombe au milieu de l'écran. Ce qu'on y voit est un angle droit net entre l'océan de la carte et **du noir pur** : `scrollView.backgroundColor = .black`.

Trois couleurs se rencontrent, et aucune ne correspond aux autres. Couleur de bord mesurée sur les quatre socles, et écart de couleur effectivement franchi à l'écran entre deux pixels voisins de part et d'autre du bord (somme des trois canaux, captures au plafond sur iPad) :

| socle | couleur de bord | écart au bord, fond `.black` | écart si le fond devenait `nightSky` |
|---|---|---|---|
| `island.png` (V, néon) | rgb(10, 8, 27) | 45 | **1** |
| `island-classic.png` (V, classique) | rgb(15, 168, 210) | **393** | 349 |
| `island-vi.png` (VI, néon) | rgb(20, 14, 53) | 87 | 43 |
| `island-vi-classic.png` (VI, classique) | rgb(44, 103, 164), non uniforme (écart interne 89) | 311 | 267 |

Le fond de l'app, lui, vaut `NCColor.nightSky` = #0A081A = rgb(10, 8, 26).

C'est la dernière colonne qui porte la décision. La carte V néon a un bord qui vaut `nightSky` **au pixel près** : son défaut est entièrement dû au fond noir et disparaît en changeant une ligne. Les trois autres ne bougent presque pas — **aucune couleur de fond unique ne peut les servir toutes**, le cyan de la V classique l'interdit. Changer le fond est nécessaire et notoirement insuffisant : il faut un vrai fondu.

Au repos, en revanche, il n'y a pas de bord du tout : vérifié au pixel sur capture, l'océan va jusqu'aux quatre bords de l'écran. Le défaut n'existe qu'en débord.

## Ce qu'on construit

### A. Le plafond devient une fonction

Une fonction pure, posée dans `MapTileSet` à côté de `level(for:)` — elle répond à la même question par l'autre bout : celle-ci dit jusqu'où on a le droit d'agrandir, celle-là quel niveau charger pour y arriver.

```
plafond = côtéSource × tolérance ÷ (côtéContenu × displayScale)
```

| carte | côté source | tolérance | iPhone ×3 | iPad ×2 |
|---|---|---|---|---|
| VI — pyramide | 18 432 | 1,10 | **3,30** | **4,95** |
| V — socle nu | 4 096 | 3,75 | **2,50** | **3,75** |

Les deux colonnes iPhone retombent exactement sur les constantes d'aujourd'hui. C'est la propriété qui rend la formule vérifiable plutôt que plausible : elle ne change rien là où rien ne devait changer, et les valeurs iPad en découlent sans être choisies.

Chaque tolérance porte sa justification, et elles diffèrent parce que les deux cartes n'ont pas la même matière :

- **1,10 sur la carte à pyramide.** Mesuré indiscernable du 1:1 à l'écran. On a les pixels, on ne les invente pas.
- **3,75 sur la carte de référence.** Ce n'est pas un choix neuf : c'est l'agrandissement que l'app montre **déjà** sur iPhone à son plafond de 2,5. L'étendre à l'iPad n'y rend rien de plus grossier — ça allonge la course sur une carte qui n'a rien de plus fin à montrer.

Le `côtéSource` vient du manifeste de tuiles quand il existe (`levels.last.side`), et du socle sinon. Le socle vaut 4 096 px, invariant déjà tenu par `MapArtResourcesTests.everyBaseImageIsShippedAtFourThousandNinetySix` — la constante est donc gardée par un test qui existe, et non par une convention.

Deux pièges à traiter explicitement :

- **`displayScale` se lit dans `traitCollection`**, jamais dans `UIScreen.main` (déprécié, et faux dès qu'un écran externe entre en jeu). Il peut changer en cours de vie — écran externe, Sidecar — donc le plafond se recalcule dans `traitCollectionDidChange`.
- **Baisser un plafond ne recadre pas le zoom courant.** `UIScrollView.maximumZoomScale` n'a pas d'effet rétroactif. Passer d'un ×2 à un ×3 fait tomber le plafond de 4,95 à 3,30 et laisserait la carte au-dessus de son propre plafond. D'où `zoomScale = min(zoomScale, maximumZoomScale)` après chaque recalcul. Le chemin qui change de CARTE, lui, passe déjà par `refit()` et n'a pas ce problème.

### B. Le fondu

Trois pièces, dont la première tient en une ligne.

**1. `scrollView.backgroundColor` : `.black` → `NCColor.nightSky`.** Corrige à elle seule la carte V néon, dont le bord vaut déjà cette couleur.

**2. Un calque de fondu, dans le conteneur zoomé, au-dessus des tuiles et sous la vue hébergée des épingles.** Cette position dans la hiérarchie — et rien d'autre — est ce qui donne « l'image s'estompe, les épingles restent nettes ». Le choix est délibéré : c'est au bord qu'on pose les propositions côtières, et une épingle qui pâlirait au moment où on la vise coûterait la précision du geste.

**3. Il peint `nightSky` avec une rampe d'alpha** : opaque au bord de la carte, transparent à 80 pt vers l'intérieur. Pas de masque à composer, pas de transparence à propager — la couleur du fond, posée par-dessus, en dégradé. Ce qui déborde de la carte est déjà `nightSky` par la pièce 1 : les deux se raccordent sans couture par construction.

**La contrainte qui commande tout le reste : 80 points d'ÉCRAN, donc pas 80 points de contenu.** Au plafond de 4,95 ils valent 16,2 pt de contenu ; au repos sur iPhone (0,427), 187. Un fondu cuit dans les PNG enflerait avec le zoom — c'est la raison pour laquelle il ne peut pas vivre dans les images, et pour laquelle le pipeline Node n'est pas touché.

Le calque est donc **contre-échelonné** : `transform = scale(1 / zoomScale)`, `bounds` = taille du contenu × `zoomScale`. Ses unités internes valent alors le point d'écran, quel que soit le zoom. Il se met à jour dans `scrollViewDidZoom`, là où le moteur travaille déjà.

Son `contents` est une image générée **une seule fois** : un carré de `2 × 80 × displayScale + 2` px, rampe opaque→transparente sur chaque bord, centre entièrement transparent, avec `contentsCenter` sur les deux pixels du milieu pour que l'étirement préserve les coins sans les déformer. Environ 0,9 Mo sur iPhone, 0,4 sur iPad ; jamais régénérée tant que `displayScale` ne change pas.

Au repos, la carte remplit l'écran : le fondu est hors champ. Il ne se voit pas et ne coûte rien — il n'apparaît qu'en débord, c'est-à-dire précisément là où est le défaut.

## Ce qui se prouve, et comment

**Hors interface, en tests unitaires :**

- `MapTileSet.maximumZoomScale` est une fonction pure : les quatre valeurs du tableau deviennent quatre assertions, plus les cas dégénérés (`displayScale` nul, côté de contenu nul, tolérance nulle) qui doivent rendre une valeur sûre plutôt que diverger.
- La géométrie du calque s'extrait de même en fonction pure, à côté de `MapGeometry.centeringInsets`. L'assertion qui compte : **la bande mesure 80 pt d'écran à tous les zooms**, du repos au plafond, sur les deux appareils. Une bande qui suivrait le zoom passerait au repos et échouerait au plafond — c'est le seul test qui distingue l'implémentation juste de la naïve.

**Au simulateur, sur les deux appareils et les quatre habillages**, avec l'instrumentation par variables d'environnement déjà écrite (`NC_MAP_TAB`, `NC_MAP_GAME`, `NC_MAP_STYLE`, `NC_MAP_DEBUG=zoom,x,y`), conservée en patch hors dépôt et **jamais commitée** :

- capture du coin de carte au plafond, et mesure de l'écart de couleur entre deux pixels voisins traversant le bord. **Critère de recette : aucun écart supérieur à 12 sur les quatre habillages**, contre 393 aujourd'hui au pire. Douze est le pas maximal d'une rampe de 80 pt qui part de 393 sur un écran ×2 (393 / 160 px ≈ 2,5 par pixel) avec la marge d'une palette 256 couleurs — un critère chiffré, pas un « ça a l'air mieux ».
- capture au plafond sur VI : les libellés de rue doivent être lisibles à 4,95 sur iPad.

Le contrôle doit être prouvé capable d'échouer avant d'être cru : la mesure d'écart de bord est passée sur les captures prises **avant** le correctif, où elle doit rapporter 45 / 393 / 87 / 311 dans l'ordre du tableau ci-dessus. Un contrôle qui ne sait qu'approuver est indiscernable d'un bon.

## Ce qu'on ne fait pas

- **Pas de fondu au repos.** Il n'y a pas de bord au repos, c'est mesuré. Un fondu permanent sur les bords de l'écran serait une décoration, pas une correction.
- **Pas de fondu sur les épingles.** Arbitré ci-dessus.
- **Pas de retouche du centrage.** Le débord d'une demi-fenêtre est un acquis du chantier précédent, et c'est lui qui rend le bord atteignable — donc visible. On corrige ce qu'il a révélé, pas lui.
- **Aucune régénération d'image.** Ni socle, ni tuile, ni manifeste. Le pipeline Node n'est pas touché.
- **Pas de réglage de contraste ou de coloris**, ni en amont (palette de `gtavi-restyle.mjs`) ni à l'exécution (courbe appliquée au décodage). Les deux voies restent ouvertes et sont documentées ci-dessous, mais elles relèvent d'une spec à part.

## Note pour plus tard : les coloris restent modifiables

Consigné ici parce que la question s'est posée en séance et que la réponse n'est pas évidente depuis le code.

**En amont, recolorisation par élément.** `gtavi-restyle.mjs` classe chaque pixel (WATER, ROAD, STREET, URBAN, LAND, SAND, DARK, LABEL) puis peint depuis huit couleurs nommées en tête de fichier. Le contraste des routes se règle donc sans toucher à l'eau. Régénérer ne demande pas de re-télécharger : `tools/basemap/.cache` conserve l'assemblage z6 (`stitched-normal.raw`, 1 170 Mo), et la chaîne est prouvée déterministe. Le coût réel est de re-commiter ~44 Mo de PNG. Limite : **l'habillage classique est la source non restylée**, la palette ne l'atteint pas.

**À l'exécution, réglage global.** Une courbe de contraste ou de saturation appliquée au décodage de chaque tuile serait réversible et réglable en direct, sur les quatre habillages — mais globale, sans séparer l'eau des routes. Piège à ne pas réapprendre : `CALayer.filters` existe dans l'API et **n'est pas appliqué sur iOS**. La voie est le décodage, jamais la composition.

## Portée

`NeonCompass/Core/Map/MapScrollView.swift`, `MapTileSet.swift`, `MapGeometry.swift`, et leurs tests. Aucun fichier de contenu, aucune migration, aucune chaîne localisable.
