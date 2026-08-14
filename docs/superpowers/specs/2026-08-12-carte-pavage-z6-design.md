# Carte de Leonida en pavage z6 — haute définition, mémoire bornée

**Statut** : validé le 2026-08-12.
**Remplace** : l'étage `.full` de `2026-08-11` (image entière de 8 192 px), livré par la PR #110.
**Ne remplace pas** : l'étage réduit, qui devient le socle du pavage.

## Pourquoi rouvrir

La PR #110 a sorti le décodage du fil principal et ramené la mémoire au repos de
319 à 125 Mo. Elle laisse deux choses en l'état : au zoom maximal on paie encore
256 Mo, et surtout **la carte n'est pas assez nette là où l'on pose les épingles**.

L'écran de la carte est l'endroit où tous les POI sont soumis. C'est la
justification, et elle porte tout le reste de ce document : la définition n'y est
pas un confort, c'est la précision du geste.

## Ce que la mesure a tranché

### Le format n'est pas le problème — PNG est déjà le meilleur

Même image de 8 192 px, réencodée dans chaque format candidat, décodage
chronométré jusqu'aux pixels en main (M1 Pro, `scratchpad/formats.swift`) :

| format | poids | décodage | écart max vs source |
| --- | --- | --- | --- |
| **PNG palette-256 (embarqué)** | **5 708 Ko** | **92 ms** | — (sans perte) |
| HEIC q=1,0 | 11 491 Ko | 752 ms | 2/255 |
| HEIC q=0,9 | 4 706 Ko | 692 ms | 108/255 |
| HEIC q=0,7 | 2 786 Ko | 748 ms | 106/255 |
| JPEG q=0,9 | 7 077 Ko | 326 ms | 106/255 |
| JPEG q=0,75 | 5 575 Ko | 326 ms | 116/255 |

Le PNG gagne sur les trois axes à la fois, contre l'intuition. Deux raisons :

1. **Le HEIC n'est pas accéléré à cette taille.** « HEVC donc décodeur matériel »
   tombe à 8 192² : ça dépasse le chemin matériel et retombe en logiciel, la
   conversion YUV→RGB s'ajoutant par-dessus. Contrôlé pour écarter un artefact de
   mesure : décodage paresseux à 0 ms pour les trois formats, tout l'écart
   apparaît à l'accès aux pixels (PNG 97 ms, JPEG 258, HEIC 849) — et cet accès,
   l'app le paie de toute façon au premier dessin.
2. **Une carte plate est le pire cas du codage avec perte.** Aplats de couleur et
   libellés fins produisent du ringing. À q=0,9 le HEIC est plus léger que notre
   PNG, mais 2,77 % des pixels dévient de plus de 8/255, avec des pointes à 108 —
   sur les libellés, précisément là où l'on veut zoomer.

Le seul avantage réel des formats avec perte est le sous-échantillonnage à la
lecture, que le PNG refuse (`kCGImageSourceSubsampleFactor` ignoré, vérifié). Il
répond à un problème que les fichiers `-reduced` ont déjà réglé, sans rien
dégrader.

**Décision : PNG palette-256 partout, y compris pour les tuiles. Ne pas
relitiger sans une mesure qui contredise ce tableau.**

### Le plafond, ce sont les 4 octets par pixel

| définition | bitmap résident |
| --- | --- |
| 8 192 px | 256 Mo |
| 12 288 px | 576 Mo |
| 20 224 px | 1 560 Mo |

Aucun format n'y change rien : tous rendent le même bitmap. Un fichier plus gros
ne fait que déplacer le moment où iOS tue l'app. **La haute définition ne
s'achète pas en changeant de codec, elle s'achète en ne décodant que le visible.**

### Le z6 existe, et les tuiles sont moins chères que l'image entière

Sondage du serveur de tuiles : la grille z6 de `YANIS/v14` est **79×79**, soit
**20 224 px** — 2,5× notre définition actuelle.

Mesure du régime en tuiles (`scratchpad/tiles.swift`) :

| | image entière (aujourd'hui) | pavage |
| --- | --- | --- |
| décodage à l'affichage | 121 ms | **11,6 ms** (16 tuiles de 512) |
| mémoire résidente | 125 Mo au repos, 318 au zoom | **16 Mo**, quelle que soit la définition |
| définition maximale | 8 192 px (plafond dur) | 20 224 px, extensible |

Une tuile de 512 px : 1,14 ms, 33 Ko. **Le pavage est simultanément plus rapide,
plus léger et plus net.** C'est rare, et c'est ce qui rend la décision facile.

### Poids du pavage, ancré sur la carte entière

Trois mesures successives, la dernière seule faisant foi — les deux premières
sont conservées ici parce que leurs erreurs sont instructives :

1. Extrapolation depuis des découpes de l'image 8 192 px : **~50 Mo**. Faux — un
   pixel de cette image porte bien plus de détail qu'un pixel z6 réel.
2. Vraies tuiles z6 quantifiées, région terrestre dense : **17–22 Mo**. Toujours
   biaisé — l'échantillon ignore l'océan, qui couvre l'essentiel de la carte.
3. Pavage de la carte entière, océan compris (`scratchpad/pyramid-full.mjs`) :

| | z6 (20 224) | z5 | z4 | z3 | pyramide |
| --- | --- | --- | --- | --- | --- |
| restylée | 21,1 Mo | 7,5 | 2,7 | 0,9 | **32,2 Mo** |
| classic | 19,2 Mo | 7,0 | 2,5 | 0,9 | **29,6 Mo** |

Réserve : le niveau z6 est extrapolé depuis l'image 8 192 px, qui est un
sous-échantillonnage du z5 et ne porte donc pas le détail supplémentaire du vrai
z6. **Le chiffre réel sera plus haut — 22 à 28 Mo par carte.** Le générateur
affichera le poids obtenu ; si la pyramide dépasse 40 Mo par carte, on
en discute avant d'embarquer.

Budget attendu : ~70 Mo pour les deux pyramides, moins les 10,9 Mo d'images
8 192 px supprimées. L'app passe de 76 à ~135 Mo.

**38 % des tuiles z6 sont de l'océan uni** — c'est une économie à prendre, voir
plus bas.

## Architecture

### Le socle et les tuiles

Deux couches superposées dans le `UIScrollView` déjà en place :

- **Le socle** — l'image réduite actuelle (`island-vi-reduced.png`, 4 096 px,
  2,1 Mo), décodée hors du fil principal comme aujourd'hui. Elle couvre toute la
  carte, tout de suite. C'est elle qui garantit qu'il n'y a **jamais de carte
  blanche et donc jamais d'écran de chargement à ajouter**.
- **Les tuiles** — une couche de tuiles dessinée par-dessus, qui ne charge que la
  fenêtre visible au niveau de détail voulu.

### Pourquoi PAS `CATiledLayer`

Le pavage a déjà existé dans ce projet et a été **retiré** le 2026-07-24
(`docs/superpowers/plans/2026-07-24-plan-map-engine-rebuild.md`, recherche dans
`.superpowers/sdd/map-architecture-research.md`), pour trois raisons. Il faut les
reprendre une par une avant de revenir en arrière :

1. **« Mauvais outil pour une image bornée de 2 048 px (500 Ko). »** La prémisse
   est morte : la carte visée fait 20 224 px, soit 409 mégapixels et 1,5 Go une
   fois décodée. C'est précisément le document que `CATiledLayer` existe pour
   servir. La recherche l'avait d'ailleurs anticipé — « si l'art grandit assez
   pour que ça compte, faire un mip manuel à 2–3 étages » — et c'est exactement
   ce qu'a livré la PR #110. Ce mip manuel ne passe pas l'échelle : on ne tient
   pas 1,5 Go, quel que soit le nombre d'étages.
2. **Le plafond `maximumZoomScale = 1`.** Artefact de l'ancienne pyramide sur un
   art de 2 048 px, où le niveau natif tombait pile à l'échelle 1. Avec 20 224 px
   dans un espace de 2 048 pt, l'échelle native est 9,875 — un plafond à 3,3 est
   très en dessous. L'objection ne mord plus.
3. **La classe de plantage iOS 26 sous SwiftUI.** ⚠️ **Celle-ci tient toujours**,
   et elle décide. Le fil Apple
   ([developer.apple.com/forums/thread/820296](https://developer.apple.com/forums/thread/820296))
   décrit `NSInternalInconsistencyException` — « Modifications to the layout
   engine must not be performed from a background thread after it has been
   accessed from the main thread » — déclenchée par
   `_UIHostingView.layoutSubviews()` depuis le fil `CAImageProviderThread`. Un
   ingénieur Apple a demandé un rapport de bug ; **aucune résolution, aucun
   correctif dans une 26.x** au 2026-08-12. L'auteur précise que la même pile en
   **UIKit pur ne reproduit pas** : c'est l'hébergement SwiftUI qui déclenche.

Or notre pile est mot pour mot celle qui plante : `CATiledLayer` dans un
`UIScrollView`, avec un `UIHostingController` dans la même hiérarchie. Et nous
sommes iOS 26 exclusivement, sans chemin de repli. **Ce n'est pas un risque
résiduel à accepter, c'est la configuration reproductrice.**

### Pavage manuel, en couches ordinaires

Les tuiles sont donc des `CALayer` ordinaires, ajoutées et retirées depuis le
**fil principal** dans les rappels de défilement et de zoom du `UIScrollView`
déjà en place. Le décodage d'une tuile se fait hors du fil principal — comme le
socle aujourd'hui — mais **la mutation de l'arbre de couches, jamais**.

Ce n'est pas un contournement au rabais, c'est meilleur sur trois points :

- **Pas de `draw(_:)` en arrière-plan, donc pas de `CAImageProviderThread`** — la
  classe de plantage ne s'applique pas, par construction et non par réglage.
- **Le fondu nous appartient.** Le « pop-in » était l'objection n°1 de la
  recherche de juillet contre `CATiledLayer` ; en posant les tuiles nous-mêmes on
  choisit quand et comment elles apparaissent, et le socle en dessous fait que
  rien n'est jamais vide.
- **Le choix de niveau devient une fonction pure**, donc testable — quel niveau
  pour quelle échelle, quelles tuiles pour quel rectangle. Le comportement de
  `CATiledLayer` est opaque et ne se teste que visuellement.

Le prix est réel : environ 250 lignes de gestion de cycle de vie des tuiles à
écrire et à tester, là où `CATiledLayer` en aurait demandé vingt. C'est le bon
échange contre un plantage non corrigé sur notre unique OS cible.

Le socle n'est pas un filet de sécurité : il est dessiné en permanence sous les
tuiles. Il couvre le fondu d'apparition, les tuiles d'océan omises, et le premier
affichage. Une carte sans pyramide (la carte de référence GTA V, 4 096 px)
n'affiche que son socle — **un seul chemin de rendu, une seule condition**,
exactement le repli que `MapArtLoader.imageURL` pratique déjà entre `-reduced` et
natif.

**Les niveaux et pourquoi ceux-là.** La pyramide descend jusqu'à z3 (2 528 px) et
non jusqu'au socle. C'est nécessaire, pas prudent : on choisit le niveau qui
correspond à l'échelle courante, ce qui borne le nombre de pixels décodés au
nombre de pixels affichés. Si le niveau le plus grossier était z5, un
zoom à peine supérieur au repos — où la fenêtre couvre encore presque toute la
carte — obligerait à décoder l'essentiel de z5, soit 102 Mpx et 409 Mo. **C'est
l'écart entre les niveaux qui borne la mémoire, pas leur nombre.** Quatre niveaux
en facteur 2, plus le socle en dessous.

### Insertion dans l'existant

Aujourd'hui l'image est un `Image(uiImage:)` au fond de la pile SwiftUI hébergée
(`MapScrollView.swift:182`), les épingles étant posées par-dessus dans le même
`UIHostingController`. La couche de tuiles s'insère **sous** la vue de ce
contrôleur, les deux dans un conteneur commun qui devient la cible du zoom
(`viewForZooming`).

Conséquence voulue : **les épingles ne changent pas d'un pouce.** Elles restent
du SwiftUI au-dessus, avec la même géométrie et le même code de placement. Tout
ce document ne touche qu'au fond de carte.

**Ce qui disparaît.** `MapArtDetail` n'a plus de raison d'être : son étage
`.full` désigne les 8 192 px, qui cessent d'exister, et il ne resterait qu'un
seul cas. Le type, le sélecteur `MapArtDetailSelector` et son hystérésis sont
supprimés — la couche de tuiles fait ce travail à une granularité bien plus fine.
`MapArtLoader`
se réduit à « décoder le socle de cette carte, hors du fil principal », c'est-à-dire
au repli `imageURL` qu'il pratique déjà. **C'est une simplification nette du
travail livré par la PR #110, pas une couche de plus.**

**D'où vient le socle.** Les images de 8 192 px sortent de
`Resources/MapArt/` : elles ne sont plus un chemin de rendu. `reduce-mapart.mjs`
disparaît donc avec sa source, et c'est le nouveau générateur qui produit le
socle de 4 096 px, au même titre que les niveaux de la pyramide. Le 8 192 px
reste un artefact du pipeline — utile comme preuve de restylage et comme
référence de non-régression — mais hors du dossier embarqué.

### Zoom maximal : 2,5 → 3,3

Ce n'est pas un réglage arbitraire. L'espace de contenu fait 2 048 pt et
l'iPhone affiche à 3× : au zoom *z* l'écran réclame `2048 × z × 3` pixels.

- Aujourd'hui, à 2,5 : 15 360 pixels réclamés pour 8 192 disponibles —
  **on agrandit 1,87×.** C'est *ça* que l'on perçoit comme un manque de
  définition, et non le format.
- À 3,3 : 20 275 réclamés pour 20 224 disponibles. **C'est le point exact où
  l'on cesse d'agrandir.**

L'iPad Pro affiche à 2× et est donc moins exigeant : l'iPhone dicte la valeur.

Monter au-delà de 3,3 reste possible — le flou revient, mais les cibles
grossissent, ce qui aide à poser une épingle. C'est un réglage d'une ligne, à
trancher à l'usage une fois le pavage en place, pas maintenant.

### Tuiles omises

Une tuile dont tous les pixels tiennent dans un écart de 2/255 autour d'une même
couleur n'est pas écrite. Le manifeste enregistre sa couleur de remplissage, et
la couche la peint d'un aplat — `backgroundColor` sur un `CALayer` vide, sans
image ni décodage. Exact, et gratuit.

Ce n'est pas un filet : à z6, 38 % des tuiles sont dans ce cas. C'est
l'économie la plus rentable du lot, et elle ne dégrade rien puisque la couleur
est reproduite exactement.

## Pipeline

Nouveau générateur `tools/basemap/gtavi-tiles.mjs`. Deux contraintes relevées
dans `gtavi-restyle.mjs` dictent sa forme :

1. **Le restylage travaille en voisinage 5×5** (reclassement au voisin dominant,
   effacement de grille au seuil 80 % sur fenêtre 5×5). Restyler tuile par tuile
   produirait des coutures visibles. Le restylage se fait donc **par bandes
   horizontales avec un halo de 2 px** de part et d'autre, rogné après coup.
2. **Il utilise des repères en coordonnées globales** — `width * 0.82`,
   `height * 0.79` pour épargner puis effacer le panneau de légende. Chaque bande
   doit donc connaître sa position et les dimensions de l'image entière ; ces
   repères ne peuvent pas être calculés localement.

Le traitement par bandes n'est pas seulement une commodité mémoire : un buffer
de 20 224² en RGB fait 1,2 Go, ce que la machine encaisse, mais on ne veut pas
que le pipeline dépende de ça.

Étapes : téléchargement des 6 241 tuiles source (avec cache disque, le serveur
est tiers et lent) → recollage → restylage par bandes → réductions lanczos3
successives pour les niveaux z5, z4, z3 **et le socle de 4 096 px** → découpe des
niveaux en tuiles de 512 px → encodage PNG palette-256 → manifeste. Le socle
sort en une seule image, pas en tuiles : c'est ce qui le rend décodable d'un
coup, hors du fil principal, avant toute tuile.

La taille de tuile est **512 px** : mesuré à 0,0436 octet/px contre 0,0470 pour
256 px, avec 1 600 fichiers au lieu de 6 241 au niveau z6.

Le générateur produit les deux habillages. `--classic` conserve les couleurs de
l'auteur d'origine et ne fait que recadrer, comme aujourd'hui.

## Position IP

Les deux habillages sont pavés, y compris `classic`. Ce point a été soulevé puis
tranché explicitement le 2026-08-12 :

- « Communautaire » ne veut pas dire libre de droits — une carte de fans reste
  protégée par défaut, et la licence de YANIS n'a pas été retrouvée.
- Mais l'écart réel est faible : `island-vi-classic.png` est **déjà** embarqué
  dans le binaire. Le paver change le *comment*, pas le *quoi*.
- La v15 de la carte source est annoncée. Disposer d'un pipeline qui sait relire
  et transformer vaut mieux qu'un fichier figé — c'est la raison qui a emporté la
  décision.

`SOURCES.md` est mis à jour : contacter l'auteur avant la v15 est le bon moment,
et les trois issues déjà listées (attribuer / retirer / redessiner) restent
ouvertes. Rien ici ne les referme.

## Tests

- **Intégrité du pavage** (extension de `MapArtResourcesTests`) : pour chaque
  carte et chaque niveau, le nombre de tuiles attendu, aucun trou dans la grille
  hors tuiles omises déclarées au manifeste, et la définition annoncée.
  Il doit échouer en nommant la tuile manquante et la commande à relancer —
  sans quoi l'app afficherait un carré vide sans aucun symptôme au build.
- **Calcul tuile ↔ zoom** : la seule vraie logique du lot. Quel niveau pour
  quelle échelle, quelles tuiles pour quelle fenêtre, aux bords compris.
- **Cohérence du manifeste** : couleur de remplissage déclarée pour toute tuile
  omise, et réciproquement.
- Chaque contrôle doit être **mis en échec exprès** avant d'être cru.

## Risques

**Le pipeline, pas l'app.** Le téléchargement des 6 241 tuiles source et le
restylage par bandes sont une réécriture non triviale de `gtavi-restyle.mjs`.
C'est là que le temps passera. Contrôle de non-régression : restyler l'image
8 192 px par bandes doit reproduire `island-vi.png` **au pixel près**. Tant que
cette égalité n'est pas obtenue, le passage par bandes est faux.

**Le poids.** ~135 Mo pour une app financée par la pub. Si la pyramide réelle
dépasse 40 Mo par carte, on rediscute avant d'embarquer — la porte de sortie
restant Supabase Storage pour les niveaux hauts, ce qui est déjà la doctrine du
projet pour le contenu.

**Le fondu des tuiles.** Le décodage étant hors du fil principal, les tuiles
apparaissent progressivement. C'est le comportement de toutes les cartes (Plans,
Google Maps) et il reste préférable à un gel de 300 ms, mais c'est un changement
visible qu'il faut regarder en vrai avant de le déclarer bon.

**Le cycle de vie des tuiles, écrit à la main.** C'est le prix du refus de
`CATiledLayer` : ajouter, retirer, réutiliser et annuler des couches au fil du
défilement, sans fuite ni scintillement. Le garde-fou est que le choix « quel
niveau, quelles tuiles » est une fonction pure, testée hors interface ; ne reste
en visuel que la pose elle-même.

## Ce que ce document ne change pas

- La carte de référence GTA V (`island.png`, 4 096 px) reste une image unique.
- Les épingles, leur placement, leur regroupement, leur soumission.
- Le format : PNG palette-256, question close.
- L'absence de `NavigationStack` dans les écrans d'onglet, et donc l'absence de
  toolbar sur l'écran de carte.
