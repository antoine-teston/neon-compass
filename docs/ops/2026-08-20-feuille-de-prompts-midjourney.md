# Feuille de prompts Midjourney — à suivre dans l'ordre

Feuille d'exécution. Le **pourquoi** de chaque choix est dans
`2026-08-19-banque-images-prompts-et-themes-pro.md` ; ici il n'y a que ce qui se
colle. Les deux fichiers doivent bouger ensemble.

**Rappel de licence** : le palier Basic suffit (« You own all Assets You
create », sans distinction de palier ni attribution). Seule réserve à trancher
avant de souscrire — la clause qui impose Pro à tout *employé* d'une société de
plus d'un million de dollars de chiffre d'affaires.

**Hygiène** : paramètres à la fin, un espace avant les tirets, aucune
ponctuation à l'intérieur. Dégrossir en `--draft` (moitié moins cher), ne
repasser en qualité pleine que sur la composition retenue.

---

## Étape 0 — L'image d'ancrage

**À faire en premier, et à ne pas bâcler : tout le lot en hérite.** Itérer
jusqu'à ce qu'elle plaise vraiment, puis garder son URL — elle devient le
`--sref` de toutes les scènes.

```
wet street at dusk in a humid subtropical American city, an invented man in a faded pastel shirt waiting alone at the kerb with his back to us, a low roadside motel behind him with faded turquoise doors and a blank unlit sign board, an invented boxy 1990s coupe parked under a street lamp, tall palms in silhouette, storm clouds breaking over a magenta and orange sky, chrome and puddles holding the colour, cracked asphalt, power lines, 35mm film still, cinematic location scouting photograph, fine grain, halation, subtle anamorphic flare, weathered and lived in --ar 16:9 --raw --s 60 --c 0 --no text letters words numbers signage logos brands badges emblems watermark signature tattoos smartphones LED modern cars 3d render cgi
```

> Noter l'URL ici une fois retenue : `ANCRAGE = ________________`

---

## Étape 1 — Les deux bannières câblées

Ce sont les seules dont un emplacement existe **déjà dans l'app**, avec un
gabarit provisoire à remplacer. Format 5:2.

### `artwork-paywall` — l'écran de vente

```
warm dusk over an invented palm lined coastal boulevard, an invented woman leaning on the open door of a parked coupe watching the sun go down, seen from behind, low sun burning orange through haze, chrome and glass catching the last light, deep magenta sky above, empty road, aspirational and cinematic, 35mm film still, fine grain, halation, weathered and lived in --ar 5:2 --raw --s 60 --c 0 --sref ANCRAGE --no text letters words numbers signage logos brands badges emblems watermark signature tattoos smartphones LED modern cars 3d render cgi
```

### `artwork-disclaimer` — le premier écran

```
calm dawn over invented subtropical wetlands, low mist on still water, pale rose and grey sky, distant palm silhouettes, quiet and unhurried, nothing man made in frame, nobody in frame, 35mm film still, fine grain, halation --ar 5:2 --raw --s 60 --c 0 --sref ANCRAGE --no text letters words numbers signage logos brands badges emblems watermark signature tattoos smartphones LED modern cars 3d render cgi
```

**Après génération, pour les deux** — recadrage, étalonnage, voile, HEIC :

```sh
magick brut.png -resize 1600x640^ -gravity center -extent 1600x640 \
       -modulate 96,120,100 base.png
magick -size 1600x640 gradient:'rgba(10,8,26,0)-rgba(10,8,26,0.55)' scrim.png
magick base.png scrim.png -compose over -composite -alpha off out.png
sips -s format heic -s formatOptions 70 out.png --out artwork-paywall.heic
magick artwork-paywall.heic -alpha off -colorspace Gray \
       -format 'moy=%[fx:mean]\n' info:     # doit rester < 0,35
```

Déposer dans `NeonCompass/Resources/Assets.xcassets/Artwork/artwork-<nom>.imageset/`,
en écrasant le gabarit et **en gardant le nom de fichier**. Aucun code à toucher.
`NCArtworkTests` refuse une image trop claire.

---

## Étape 2 — Les six en-têtes d'actu (16:9)

Six rubriques, **six lumières différentes** — c'est le lot qui fera le plus pour
la cohérence perçue. Ajouter à chacun : `--raw --s 50 --c 0 --sref ANCRAGE` et
le bloc `--no` commun.

| # | Rubrique | Prompt |
|---|---|---|
| 1 | `announcement` | `empty coastal highway at dawn beneath a colossal blank billboard on rusted steel stilts seen from below, nobody in frame, pink grey pre sunrise sky, low mist over flat calm water, distant palms, nothing written anywhere, monumental and silent --ar 16:9` |
| 2 | `patch` | `open roll up door of a roadside repair garage at high noon, an invented mechanic in oil stained coveralls crouched at a wheel arch with his back to us, blinding white sunlight on cracked concrete outside, cool dark cluttered interior with a hydraulic lift and scattered tools, heat shimmer, oil stains, chain link fence --ar 16:9` |
| 3 | `event` | `floodlit stadium parking lot at blue hour, small groups of invented people walking between the rows of parked cars towards the light, all seen from behind at distance, tall light masts blazing, orange sodium pools on wet asphalt, deep indigo sky --ar 16:9` |
| 4 | `guide` | `lonely junction on a raised swamp causeway under flat pewter storm light, a lone invented figure standing at the fork looking down one of the two roads, seen from behind at distance, bald cypress and mangrove, standing black water, leaning telegraph poles, blank unmarked direction signs, no horizon glow --ar 16:9` |
| 5 | `business` | `vast empty strip mall parking lot at high noon, faded painted lines on cracked asphalt, abandoned shopping carts, blank white signage boards with nothing on them, dusty palm row, heat shimmer, utterly deserted, nobody in frame --ar 16:9` |
| 6 | `community` | `beachfront boardwalk at golden hour, invented people walking and sitting along the promenade and two of them leaning on the chrome railing, seen from behind and in profile at distance, long raking shadows across weathered planks, warm orange light through palm fronds, lens flare --ar 16:9` |

**Bloc commun à coller à la suite de chacun :**

```
35mm film still, cinematic location scouting photograph, fine grain, halation, subtle anamorphic flare, weathered and lived in --raw --s 50 --c 0 --sref ANCRAGE --no text letters words numbers signage logos brands badges emblems watermark signature tattoos smartphones LED modern cars 3d render cgi
```

Post-traitement : même recette qu'à l'étape 1, en `1600x900`. **Le tiers bas doit
descendre sous 0,20 de moyenne** — c'est là que le titre se pose.

---

## Étape 3 — Les six emblèmes de palier (1:1)

**Registre à part** : des objets, pas des lieux. Pas de `--raw`, pas de `--sref`
de l'ancrage — l'ancrage photographique les abîmerait. Générer le n° 1 d'abord,
garder SON url comme `--sref` pour les cinq autres.

Base commune, à préfixer à chaque sujet :

```
collectible enamel pin badge, polished chrome bezel with coloured enamel inlay, warm rim light from upper left, centred and alone, front facing, perfectly symmetrical, no perspective, no cast shadow, bold thick shapes readable when tiny, product photograph on a pure flat black background
```

| # | Palier | Sujet |
|---|---|---|
| 1 | `tourist` | `a plain circular chrome ring enclosing a single pair of crossed palm fronds in pale teal enamel, dull unpolished chrome, the humblest badge of a set` |
| 2 | `runner` | `brighter chrome ring enclosing crossed palm fronds with three short cyan enamel speed dashes across the lower left, a first hint of polish` |
| 3 | `getawayDriver` | `polished chrome hexagon enclosing an upward chevron in warm orange enamel, thin magenta enamel inlay following the bezel` |
| 4 | `heister` | `faceted chrome shield enclosing a hexagon, deep magenta and violet enamel, every edge catching light` |
| 5 | `lieutenant` | `chrome shield bearing a four pointed star with two small chrome wings at its sides, violet enamel fading into warm orange, highly reflective` |
| 6 | `kingpin` | `ornate chrome shield with a radiant crown rising above it in warm gold toned chrome, magenta to violet to orange enamel, thin engraved rays fanning out behind` |

**Paramètres :** `--ar 1:1 --s 250 --c 0 --no text letters words numbers logos faces people background gradient vignette glow reflections scenery`

Le fond noir plat est une **exigence technique** : le détourage en dépend.

---

## Étape 4 — Les quatre icônes d'app (1:1)

Registre graphique. Lisible à 40 px : trois formes, pas plus. Pas de `--sref`.

```
flat vector app icon, bold graphic emblem, thick clean strokes, high contrast, centred symmetrical composition, full bleed artwork reaching all four edges, a stylised chrome compass rose seen perfectly face on silhouetted against a large setting sun disc, two palm silhouettes flanking it low in the frame --ar 1:1 --s 300 --c 0 --no text letters numbers photorealism detail clutter rounded corners padding border frame drop shadow mockup transparency
```

| Icône | Ajouter au prompt |
|---|---|
| primaire | `cyan compass, magenta to orange sun, near black sky` |
| `AppIcon-MagentaDrift` | `magenta compass, violet to magenta sun, violet palms` |
| `AppIcon-SunsetOverdrive` | `warm orange compass, orange to yellow sun, deep magenta palms` |
| `AppIcon-CyanPulse` | `bright cyan compass, violet to cyan sun, pale cyan palms, the coldest of the four` |

**Retirer l'alpha est obligatoire** — une icône avec canal alpha fait rejeter la
soumission :

```sh
magick brut.png -resize 1024x1024^ -gravity center -extent 1024x1024 \
       -background '#0A081A' -alpha remove -alpha off AppIcon-1024.png
magick identify -format '%[channels]\n' AppIcon-1024.png   # doit dire srgb
```

---

## Étape 5 — Les trois fonds d'ambiance Pro (1:1)

**Le bloc de style ne s'applique pas** : ni grain, ni netteté, ni `--sref`. Ce
sont des lieux vus hors mise au point, si flous qu'aucun sujet ne se lit.

```
extreme bokeh, completely out of focus, no subject, no focal point, no horizon, soft bleeding light only, very dark and very low contrast, the brightest pixel still dim, near black --ar 1:1 --raw --s 40 --c 0 --no text letters sharp focus detail subject horizon people faces objects
```

| Fond | Sujet, entièrement défocalisé |
|---|---|
| `magentaDrift` | `the underside of a concrete overpass at night in heavy rain, distant magenta signage bleeding through the downpour, deep violet shadow pooling below` |
| `sunsetOverdrive` | `the last ten minutes of dusk over an open swamp, dying warm orange along the bottom edge fading up into deep indigo, cypress shapes dissolved into nothing` |
| `cyanPulse` | `an empty swimming pool lit from underwater at night, cold cyan light rippling upward, deep violet darkness all around` |

**Contrôle** : réduire à 100 px de large. S'il reste lisible comme une image,
c'est trop chargé — relancer.

---

## Étape 6 — Le bandeau Social (21:9)

```
elevated night view along a coastal causeway, chains of warm sodium street lights receding into the distance, dark water on both sides, distant city glow low on the right, deep indigo sky, nobody in frame --ar 21:9 --raw --s 50 --c 0 --sref ANCRAGE --no text letters words numbers signage logos brands badges emblems watermark signature tattoos smartphones LED modern cars 3d render cgi
```

Tiers gauche presque noir, tiers droit la lueur de la ville, **rien au centre** —
un titre s'y pose.

---

## Avant de garder une image, trois questions

1. **Une lettre, un écusson, un logo quelque part ?** Relancer. Échec le plus
   fréquent et le plus disqualifiant.
2. **Un anachronisme ?** Écran plat, phare à LED, téléphone moderne. Relancer en
   renforçant le `--no`.
3. **Est-ce que ça ressemble à quelque chose de précis** — une voiture qu'on
   pourrait nommer, un visage qu'on croit reconnaître, une jaquette connue ?
   Relancer. Seule des trois à demander un jugement, et la seule qui compte.

Toute image conservée va au §8 de l'autre document, **avec son Job ID** :
horodaté chez l'éditeur et rattaché au compte, c'est une preuve de provenance
plus solide qu'une ligne que nous écrivons nous-mêmes.
