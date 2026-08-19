# Provenance des fonds de carte

Ce fichier existe pour la même raison que l'archivage des prompts d'images
génératives demandé par `CLAUDE.md` : pouvoir dire, des mois plus tard et sans
relire le code, d'où vient chaque pixel embarqué dans l'app et ce que nous en
avons fait. Il décrit l'état réel, y compris ce qui n'est pas réglé.

## `island.png` / `island-classic.png` — carte de référence (GTA V)

- Source : tuiles slippy `s3-eu-west-1.amazonaws.com/gtavmap/tiles`, style
  `atlas`, z6 (576 tuiles, 6 144 px). Générateur : `gtav-map.mjs`.
- `island.png` est restylée (`gtav-restyle.mjs`) : classification par pixel puis
  remplacement complet par la palette Neon Compass.
- `island-classic.png` est la carte source, recadrée et redimensionnée. Les
  couleurs sont celles de l'auteur d'origine.

## `island-vi.png` / `island-vi-classic.png` — carte de Leonida (GTA VI)

- Source : tuiles slippy `map.stateofleonida.net/tiles/YANIS/v14/normal`,
  **z6** (6 241 tuiles, 79 × 79, 20 224 px). Carte communautaire de fans,
  dite « YANIS », dont la v14 est la version utilisée ici. Générateur :
  `gtavi-tiles.mjs --style normal` — les deux fichiers sortent d'une seule
  exécution, plus la pyramide de tuiles décrite plus bas.
- Le brut z6 est complété à 20 480 px en océan (79 tuiles au lieu des 80
  qu'une grille pleine aurait), traité par quatre quadrants à halo via
  `gtavi-transform.mjs` (classification par pixel héritée de
  `gtavi-restyle.mjs`, effacement de la grille et des lignes de comté,
  uniformisation des libellés), puis recadré sur l'île — le double exact du
  cadrage que `gtavi-map.mjs` dérive de la bbox avec la plus grande marge
  symétrique que la source autorise. Ce cadrage a changé une fois (tâche 10,
  élargissement des bordures d'océan) : toute position de POI normalisée
  avant ce commit ne désigne plus le même point et a dû être remappée.
- Chaque carte est livrée en trois paliers issus du **même recadrage**
  (19 068 px), pour qu'aucun ne dérive d'un sous-pixel par rapport aux
  autres : un socle unique de 4 096 px (`MapArt/<nom>.png`, décodé en
  permanence), et deux niveaux tuilés de 512 px (9 216 et 18 432 px, sous
  `MapTiles/<nom>/<côté>/<x>_<y>.png` ; les tuiles quasi uniformes ne sont
  pas écrites, leur couleur va dans `MapTiles/<nom>.json`).
- `island-vi.png` est restylée : palette Neon Compass, aucun pixel source ne
  subsiste tel quel.
- `island-vi-classic.png` est la carte source : panneau de légende effacé
  (même géométrie que la restylée, via `legendMask`), recadrée. **Les
  couleurs et le dessin sont ceux de l'auteur d'origine.**
- `gtavi-map.mjs` (z5, 1 600 tuiles, 10 240 px) reste dans le dépôt et
  exécutable, mais ne produit plus les fichiers embarqués : il sert de
  référence de non-régression pour `gtavi-transform.mjs`, dont la sortie
  doit rester identique à l'octet près après tout refactor du module.

## Pavage z6 (depuis le 2026-08-12)

`gtavi-tiles.mjs` remplace `gtavi-map.mjs` pour la carte de Leonida. Grille
source z6 : 79 × 79 tuiles de 256 px, soit 20 224 px, complétés en océan à
20 480 px — le double exact du z5, ce qui rend toute la géométrie du pipeline
z5 valable au facteur 2. Le traitement passe par quatre quadrants de 10 240 px
avec un halo de 1 024 px, en deux passes : le sondage de la grille de
coordonnées somme des lignes entières et ne peut pas se calculer par quadrant.

Livré : un socle de 4 096 px dans `MapArt/`, et deux niveaux de tuiles de
512 px (9 216 / 18 432) dans `MapTiles/<nom>/<côté>/`. Le niveau le plus fin
s'arrête à 18 432 parce que le recadrage de la tâche 10 n'apporte que 19 068 px
de détail réel — au-delà on interpolerait, et on ferait payer le poids de pixels
inventés. La règle vaut mieux que le nombre : **le plus grand multiple PAIR de
512 sous le côté du cadre**. Sous, pour ne jamais interpoler ; pair, pour que sa
moitié tombe elle aussi sur la grille de tuiles — 512 × 37 = 18 944 satisfait la
première contrainte et viole la seconde.

`gtavi-map.mjs` reste pour la carte de référence GTA V et comme trace du
chemin z5 ; `reduce-mapart.mjs` a été supprimé avec les deux étages.

Le socle n'est pas un niveau de plus : il est dessiné en permanence sous les
tuiles, et `level(for:)` ne rend nil que tant que l'écran ne réclame pas plus
que ses 4 096 px. Ce seuil dépend de l'ÉCRAN et non du seul zoom —
`contentSize × zoom × displayScale > 4 096`, donc zoom > 0,667 sur un appareil
3× et > 1,0 sur un 2× comme l'iPad Pro 13. Aucun document ne doit l'écrire
comme une constante.

### Poids embarqué, mesuré le 2026-08-14

`MapTiles/` pèse **44 Mo** pour **2 351 PNG** (21 Mo `island-vi`, 23 Mo
`island-vi-classic`), et `MapArt/` **8,0 Mo**, dont 4,6 pour les deux socles de
la carte GTA V, qui n'a pas de pyramide. Chiffres pris sur l'arbre du dépôt :
**ne jamais citer la taille du `.app` de Debug** (109 Mo relevés à la tâche 4),
qui n'est ni aminci ni compressé et n'est donc pas une taille de livraison.

L'élargissement du cadre de la tâche 10 (16 384 → 18 432 px) a coûté **+1,2 Mio
mesurés**, et non les ~10 Mo annoncés en séance. La règle à garder : le poids
d'un pavage suit le **contenu non uniforme**, jamais le côté du niveau. Le
surcroît de surface gagné en élargissant est de l'océan, qui part en tuiles
uniformes jamais écrites.

### Déterminisme de la chaîne, prouvé le 2026-08-14

`node gtavi-tiles.mjs --style normal` relancé sur l'arbre livré rend **zéro
fichier modifié** au `git status` : 2 351 tuiles, 2 socles et 2 manifestes
reproduits au bit près. C'était une supposition jusque-là — tout le discours
d'exactitude à l'octet de ce pipeline la faisait sans l'avoir montrée à
l'échelle du pavage.

Le filet de non-régression du z5 porte sur les **deux PNG** de
`gtavi-map.mjs --restyle --classic` écrits dans `out/` (git-ignoré), et plus sur
le manifeste, dont l'écriture a été retirée :

```
ce7c8e141e4dff2b44a31da5b69f627fa36bdeb82fd9a97620ae1cc5c5cec9df  island-vi.png
2e731c7d7ad4b9ef2c48c6432185ff53a246b846cde4e658b66a5406bc67604e  island-vi-classic.png
```

## Étage réduit — retiré

`island-vi-reduced.png` / `island-vi-classic-reduced.png` (produits par
`reduce-mapart.mjs`) n'existent plus : depuis que `gtavi-tiles.mjs` livre un
socle nativement à 4 096 px, `MapArtResourcesTests` exige au contraire leur
**absence**, sans condition — un `-reduced.png` oublié ne se verrait nulle part
et ajouterait 4 Mo au paquet pour rien.
`reduce-mapart.mjs` et le code qui décodait cet étage (`MapArtDetail`,
`MapArtDetailSelector`) ont été retirés à la tâche 8 du même chantier. Il ne
reste de l'étage réduit qu'un test, `noReducedTierSurvives`, qui interdit à un
`-reduced.png` de revenir dormir dans le paquet.

## Ce qui reste à trancher

Les deux fichiers `*-classic.png` **et tout leur pavage** ne sont **pas** un
travail transformatif de notre part : ce sont des cartes de fans tierces,
recadrées. `CLAUDE.md` exige que tout contenu soit original ou clairement
transformatif, et aucune attribution n'accompagne ces images dans l'app. Le
pavage z6 n'a pas créé ce risque, mais il l'a **multiplié par mille** en nombre
de fichiers : `MapTiles/island-vi-classic/` porte à lui seul 23 Mo et 1 197 PNG
découpés dans l'œuvre d'un tiers, là où il n'y avait qu'une image.

Trois issues, à choisir explicitement plutôt que par défaut :

1. **Attribuer** — créditer les auteurs dans un écran « Crédits » et vérifier la
   licence de chaque source (celle de YANIS n'a pas été retrouvée).
2. **Ne plus embarquer que le restylage** — les deux `*-classic.png` et leurs
   deux pyramides sortent du binaire ; l'habillage « classic » disparaît, ainsi
   que le bouton qui bascule. C'est aussi, accessoirement, 23 Mo de moins.
3. **Redessiner** un fond classic à partir de nos propres primitives.

**Le bon moment pour écrire à l'auteur de YANIS est avant la v15** : la carte va
être mise à jour, la question se reposera de toute façon, et une demande faite
avant vaut mieux qu'une régularisation après.

Tant que rien n'est tranché, ces fichiers sont le risque IP le plus concret du
dépôt, et ils étaient déjà présents pour la V avant la carte VI.
