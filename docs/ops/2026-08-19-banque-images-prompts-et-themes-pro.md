# Banque d'images : lot, prompts, et thèmes Pro

Tout est embarqué dans l'app (décision du 2026-08-19) : aucune image ne passe
par le CDN, donc aucune brique de chargement distant à écrire. Les illustrations
sont produites par génération d'image ; le choix du générateur a été tranché le
2026-08-20 et vaut par besoin plutôt qu'en bloc — voir §3.

Ce fichier est aussi l'**archive de prompts** exigée par CLAUDE.md (« prompts +
sources archivés comme preuve d'originalité »). Tout prompt réellement utilisé
doit finir ici, y compris les variantes rejetées.

---

## 1. État des lieux au 2026-08-19

Trois manques, dont deux inattendus :

| Constat | Preuve | Portée |
|---|---|---|
| **Aucun `Assets.xcassets`** dans le dépôt — pas même l'`AppIcon` primaire | `find . -name "*.xcassets"` ne renvoie rien | **Bloquant App Store** |
| L'interrupteur d'icône alternée ne fait rien | `SettingsAppearanceSection.swift:30` appelle `setAlternateIcon(named: "AppIcon-Neon")`, asset inexistant | Documenté dans `2026-07-23-alternate-app-icons.md` |
| Le sélecteur de thème n'est **pas** réservé aux Pro | `SettingsAppearanceSection.swift:8-19` : aucun contrôle de `isProEntitled` | Le paywall vend « Thèmes exclusifs » (`paywall.feature.themes`) qui n'est pas exclusif |
| Aucun `AsyncImage`, aucun champ image dans les schémas | — | Sans objet désormais : tout est embarqué |

---

## 2. Ce qu'est un thème Pro

Aujourd'hui `NCTheme` ne porte qu'une **couleur d'accent**, appliquée en
`.tint()` par `RootView` (lignes 94, 121, 222). Un menu qui change une teinte ne
vaut pas une ligne de paywall.

**Définition retenue : un thème = accent + fond d'ambiance + icône d'app.**

| Thème | Accent | Fond d'ambiance | Icône | Accès |
|---|---|---|---|---|
| `classic` *(nouveau)* | `#26F2F2` | aucun (`nightSky` uni) | primaire | **Gratuit** |
| `cyanPulse` | `#26F2F2` | `backdrop-cyanPulse.heic` | `AppIcon-CyanPulse` | **Pro** |
| `magentaDrift` | `#FF3388` | `backdrop-magentaDrift.heic` | `AppIcon-MagentaDrift` | **Pro** |
| `sunsetOverdrive` | `#FF8C40` | `backdrop-sunsetOverdrive.heic` | `AppIcon-SunsetOverdrive` | **Pro** |

**Le gratuit est un socle neutre, pas un thème amputé** (arbitré le 2026-08-19).
`classic` est exactement l'app d'aujourd'hui : fond uni, accent cyan, icône
primaire. Les trois thèmes NOMMÉS passent tous côté Pro, chacun avec son fond et
son icône — c'est ce qui rend `paywall.feature.themes` (« Thèmes exclusifs »)
vrai au pluriel, alors qu'il désigne aujourd'hui un sélecteur ouvert à tous.

La gamme s'arrête à trois. Les trois libellés sont déjà traduits en cinq langues
dans `Localizable.xcstrings` ; seul `theme.classic` est à ajouter. Élargir
ferait entrer des teintes hors de la palette, qui n'a que cinq couleurs et ne
tient que parce qu'elle est courte — `NCTheme.swift` le dit déjà : « All colors
reuse existing `NCColor` hexes — no new palette values are introduced here. »

**Le fond d'ambiance est le vrai produit.** L'app est un aplat `#0A081A` derrière
du Liquid Glass : le verre n'a rien à réfracter, donc il ne se voit presque pas.
Une nappe lumineuse derrière fait enfin exister le matériau — c'est visible
immédiatement, sur tous les écrans, ce qu'une teinte d'accent n'est pas.

⚠️ **À mesurer avant de livrer** : le verre reflouterait le fond à chaque image
d'un défilement. Compter les images perdues (méthode habituelle du projet), pas
chronométrer. Le fond reste **strictement statique** — aucun parallaxe, aucune
animation : un fond mobile sous du verre est le cas coûteux.

⚠️ **Empreinte mémoire** : `MapArtLoader.swift:14-17` mesure 127 Mo pour une
image de 4 096 px — le mur des 4 octets par pixel. Un fond en 1536×1536 pèse
≈ 9 Mo décodé, ce qui est acceptable **à condition de n'en garder qu'un seul en
mémoire**, comme le fait déjà `MapArtLoader`.

---

## 3. Quel générateur — décision du 2026-08-20

**D'abord le point désagréable : l'outil n'était pas seul en cause.** Les
prompts de la première version de ce document décrivaient de la géométrie
synthwave abstraite — grilles, soleils à lamelles, dégradés. C'est ce qui a été
demandé, c'est donc ce qui est sorti, et c'est étranger à l'ambiance visée. Le
§5 a été entièrement réécrit le 2026-08-19 autour de la bonne filiation
(photographie nocturne floridienne, affiche de voyage aérographiée des années
1980, carte postale touristique). **Avant de payer quoi que ce soit, refaire un
essai avec les nouveaux prompts** : une partie de la déception vient du brief.

Cela dit, tous les modèles ne se valent pas sur ce registre, et trois besoins
distincts appellent trois outils.

| Besoin | Outil | Pourquoi celui-là | Coût |
|---|---|---|---|
| Fonds d'ambiance, en-têtes, bandeau, icônes (14 images) | **Midjourney** | C'est son terrain le plus fort : lumière cinématographique, néon humide, matière photographique. Et `--sref <url>` verrouille un style d'une image à l'autre bien mieux qu'un « same as before » conversationnel — décisif pour deux séries de six. | palier **Basic**, résiliable après le lot — la propriété des images y survit (voir plus bas) |
| Six emblèmes de palier | **Recraft** | Seul générateur grand public à sortir du **SVG véritable** (vrais chemins, vrais points d'ancrage), pas un raster vectorisé. Voir la réouverture ci-dessous. | ~10-12 $/mois selon le palier |
| Itération à volume, brouillons, variantes | **FLUX.2 [klein] 4B en local** (Draw Things) | Gratuit, tourne sur le M1 Pro 16 Go, et **Apache 2.0 vérifié à la source** — aucune ambiguïté sur l'usage commercial. Bon pour dégrossir avant de dépenser des crédits. | 0 € |

### Le piège de licence, à ne pas rater

Un modèle libre d'accès n'est pas un modèle libre d'usage, et la famille FLUX
mélange les deux dans des noms voisins. L'app est **commerciale** (App Store,
financée par la publicité) : une image issue d'un modèle non commercial n'y a
pas sa place.

| Variante | Licence | Utilisable pour Neon Compass |
|---|---|---|
| FLUX.2 **[klein] 4B** | **Apache 2.0** — texte intégral relu sur Hugging Face le 2026-08-20, sans avenant | **Oui**, sans réserve |
| FLUX.2 [klein] 9B | FLUX Non-Commercial License | **Non** |
| FLUX.2 **[dev]** (32B) | FLUX Non-Commercial License ; poids sous accès restreint | **Non** — et c'est le plus populaire en local, donc le piège |
| FLUX.2 Pro / Max | Fermé, payant, par paliers (Builder, Professional) | Oui si souscrit |

Le seul chiffre à retenir : **klein-4B, et pas une autre**. Le nom du fichier
téléchargé fait foi ; `dev` dans le nom vaut refus.

### Midjourney : ce que disent vraiment les CGU

Vérifié le 2026-08-20 dans le texte intégral (version du 27 mai 2026, lue via
un instantané Wayback — le site refuse le chargement direct, 403). Une version
antérieure de cette section relayait une source secondaire affirmant que les
paliers d'entrée n'accordaient que des droits commerciaux « avec attribution ».
**C'est faux : le mot attribution n'apparaît nulle part dans les CGU.**

> You own all Assets You create with the Services to the fullest extent
> possible under applicable law.

Aucune distinction de palier. Le **Basic suffit** pour la licence commerciale
générale. Trois précisions qui, elles, comptent :

- **L'exception du million.** « If you are a company or any employee of a
  company with more than $1,000,000 USD a year in revenue, you must be
  subscribed to a "Pro" or "Mega" plan to own Your Assets. » La clause vise
  *l'employé*, pas seulement l'entreprise, et ne fait aucune exception pour un
  projet personnel mené en dehors du travail. **À trancher selon la situation
  de l'auteur avant de souscrire** — c'est la seule chose qui ferait basculer
  du Basic vers le Pro, et elle n'a rien à voir avec Neon Compass lui-même.
- **La propriété survit à la résiliation.** « Your ownership of the Assets you
  created persists even if in subsequent months You downgrade or cancel Your
  membership. » Le plan « un mois d'abonnement, on génère le lot, on résilie »
  est donc explicitement prévu par le contrat, pas toléré.
- **Public par défaut.** Les générations sont visibles et remixables par la
  communauté ; le mode Stealth est réservé aux paliers Pro et Mega. Sans
  conséquence pour nous : nos prompts ne nomment rien de propriétaire et sont
  archivés au §8 de toute façon.

À noter sans que ce soit bloquant : on accorde à Midjourney une licence
« perpetual, worldwide, non-exclusive, sublicensable, irrevocable » sur les
images produites, qui survit à la résiliation. Nous ne cherchons pas
l'exclusivité, mais nos illustrations ne seront jamais exclusives non plus.

### Contraintes qui ne dépendent pas de l'outil

| Contrainte | Conséquence |
|---|---|
| **Aucun texte dans les images** | La règle tient même quand le modèle sait écrire proprement : le motif n'est pas technique mais de localisation — un mot dans une image imposerait cinq variantes. |
| Cohérence de série | Générer chaque série d'un seul tenant : `--sref` sur Midjourney, une conversation unique ailleurs. C'est le seul levier fiable. |
| Transparence | Ne pas compter dessus. Le détourage du §6 est vérifié et fonctionne sur fond noir plat — c'est pourquoi les prompts d'emblèmes l'imposent. |
| **Zéro référence à la franchise dans les prompts** | Contrainte IP (CLAUDE.md), et accessoirement contrainte de qualité : les modèles commerciaux dégradent ou refusent sur un nom de franchise. On vise la *filiation*, jamais l'œuvre. |

### Réouverture : les emblèmes peuvent redevenir vectoriels

Ce document affirmait qu'aucun insigne ne pouvait être vectoriel, faute de
générateur produisant du SVG. **C'est faux depuis Recraft**, qui en produit du
véritable. Le verrou technique saute ; la question de design, elle, reste
entière, et elle ne penche pas dans le sens qu'on croirait.

- Un **`.symbolset`** serait monochrome et prendrait la teinte du thème. On y
  gagnerait `.symbolEffect`, on y perdrait l'émail coloré — c'est-à-dire ce qui
  fait qu'un badge de collection ressemble à un badge de collection.
- Un **SVG couleur en `imageset`** (Xcode sait le faire, « Preserve Vector
  Data ») garde la couleur et devient indépendant de la résolution. Mais
  l'émail et le chrome sont un rendu *spéculaire* : dégradés, reflets, arêtes
  qui accrochent la lumière. C'est précisément ce que le vectoriel rend mal.

→ **On reste au raster PNG alpha 512×512 pour la v1.** L'emblème n'est affiché
qu'à une seule taille (64 pt), où le vectoriel n'apporte rien, et 512×512 en
alpha pèse déjà peu. La piste vectorielle est notée comme **disponible**, pas
abandonnée : le jour où l'emblème apparaît à une seconde taille — un widget, ou
une célébration plein écran au franchissement de palier — c'est elle qu'il faut
reprendre.

**Décision sur la place de l'insigne (inchangée).** L'entête Profil affiche
aujourd'hui un symbole SF de 12 pt (`ProfileHeaderView.swift:140-159`), animé
par `.symbolEffect(.bounce, value: state.streetRank)` — le seul moment où l'app
célèbre quelque chose. Une image générée à 12 pt serait de la bouillie, et un
raster perdrait le rebond.

→ **On ne remplace pas le symbole, on ajoute à côté** : un **emblème couleur de
64 pt** entre dans l'entête, la capsule garde son symbole SF et son libellé. Le
rebond reste où il est, et l'emblème s'anime au `.scaleEffect` / `.phaseAnimator`
au franchissement de palier.

---

## 4. Le lot : 20 fichiers pour la v1

| # | Lot | Ratio | Taille finale | Format | Où |
|---|---|---|---|---|---|
| 1 | Icône d'app primaire | 1:1 | 1024×1024 | PNG **sans alpha** | `Assets.xcassets/AppIcon.appiconset` |
| 3 | Icônes alternées (cyan, magenta, sunset) | 1:1 | 1024×1024 | PNG sans alpha | `Assets.xcassets/AppIcon-*.appiconset` |
| 6 | **Emblèmes de palier** (`tourist` → `kingpin`) | 1:1 | 512×512 | PNG **alpha** | `Assets.xcassets/Ranks/` |
| 6 | En-têtes de rubrique Actu | 16:9 | 1600×900 | HEIC q72 | `Assets.xcassets/NewsArt/` |
| 3 | Fonds d'ambiance Pro | 1:1 | 1536×1536 | HEIC q60 | `Assets.xcassets/Backdrops/` ✅ *(gabarits en place)* |
| 1 | Bandeau hebdo Social | 21:9 | 1680×720 | HEIC q72 | `Assets.xcassets/SocialArt/` |

**Phase 2, hors v1** : 8 emblèmes de communauté (256×256 PNG alpha). Jeu fermé,
**pas d'envoi par l'utilisateur** — un upload ouvre un chantier de modération et
un risque de refus App Review sur le contenu généré par les utilisateurs.

### Tout va au catalogue d'assets — y compris le HEIC

**Révision du 2026-08-19, après mesure.** Ce document recommandait d'abord des
références de dossier (`type: folder`) pour les grandes images, en supposant
qu'un catalogue d'assets n'accepte que du PNG. C'est faux : `actool` compile un
`.heic` posé dans un `imageset` **sans erreur ni avertissement**, la rendition
est bien dans `Assets.car`, et `UIImage(named:)` la rend à l'exécution — ce
dernier point est tenu par un test (`everyPaidThemeResolvesItsBackdrop`), parce
qu'accepter un format à la compilation n'est pas le rendre au lancement.

Mesuré sur les trois fonds provisoires, en 1536×1536 :

| Format | Poids | Rapport |
|---|---|---|
| PNG-24 | 1,4 à 2,0 Mo | — |
| **HEIC q60** | **11 à 14 Ko** | **≈ 127× plus léger** |

Le catalogue gagne donc sur les deux tableaux, et il fait tomber trois
inconvénients d'un coup :

- **plus de piège de non-recopie.** `type: folder` n'est pas recopié quand son
  CONTENU change : régénérer une image puis reconstruire donnait un binaire
  portant l'ancienne, sans un mot dans le journal. Le catalogue, lui, suit ses
  fichiers. C'est le landmine le plus coûteux de ce dépôt, et les images n'y
  sont plus exposées ;
- **plus de chargeur maison.** Pas de `MapArtLoader` bis, pas de décodage à
  sortir du fil principal, pas de cache à tenir : `UIImage(named:)` s'en charge ;
- **plus de déclaration dans `project.yml`.** Le catalogue vit sous
  `NeonCompass/`, déjà un chemin source.

Reste une chose que le catalogue ne fait pas : borner l'empreinte mémoire. Un
fond de 1536×1536 pèse ≈ 9 Mo décodé, et un seul est vivant à la fois puisque
`backdropName` ne rend qu'un nom. À surveiller si la taille montait.

## 5. Les prompts

### 5.0 Direction visuelle — révisée le 2026-08-19

**Première version abandonnée.** Elle demandait du synthwave abstrait : grilles
en perspective, contours néon, schémas éclatés. C'était la mauvaise cible. Ce
qu'on veut est photographique et moite — la Floride au bord de la nuit — et un
générateur à qui on demande une grille vectorielle rend une grille vectorielle.
Les images décevantes venaient de la consigne autant que de l'outil.

**Sur la filiation.** L'ambiance recherchée ne s'obtient pas en citant un jeu :
la plupart des modèles commerciaux dégradent ou refusent sur un nom de
franchise, et CLAUDE.md l'interdit de toute façon. Elle s'obtient en nommant ses
SOURCES RÉELLES, qui sont publiques et n'appartiennent à personne — *Miami
Vice*, la photographie nocturne de Michael Mann, les affiches de voyage
aérographiées des années 80, les cartes postales de Floride. C'est plus précis
qu'un nom de marque, donc ça rend mieux.

**Une décision de charte à connaître** : les illustrations ont une gamme un peu
plus large que l'interface. Un coucher de soleil floridien composé des cinq
seules couleurs de `NCColor` paraît synthétique — il lui faut du sable, de la
crème, du turquoise profond, du gris chrome. **La palette de l'INTERFACE ne
bouge pas** ; seules les images gagnent ces neutres chauds, et les cinq teintes
de la charte doivent y rester dominantes.

#### Le préambule — à coller en tête de CHAQUE conversation

```
You are generating original artwork for an independent iOS app. These rules
apply to EVERY image in this conversation.

STYLE — the aesthetic lineage
- Sun-drenched South Florida at the edge of night: humid golden-hour and
  blue-hour light, hot pink and orange sunsets bleeding over the ocean,
  art-deco facades, neon signage burning against a bruised sky, palm
  silhouettes, chrome, wet asphalt holding colour.
- The lineage is Miami Vice, Michael Mann's night photography, 1980s
  airbrushed travel-poster art, and Florida tourist postcards.
- PAINTERLY and airbrushed, never photographic. Rich, saturated, cinematic.
  Soft gradients, glowing highlights, deep shadows that keep their colour.
- Fine film grain throughout. Warm atmospheric haze. Anamorphic lens flare,
  sparingly.
- Dark overall. These images sit on a near-black interface and must never
  brighten it.

PALETTE — anchored, not limited
These five belong to the app and must dominate every image:
  near-black    #0A081A
  neon magenta  #FF3388
  electric violet #8C33F2
  warm orange   #FF8C40
  neon cyan     #26F2F2
You MAY add, sparingly, the warm neutrals the light requires: sand, cream,
deep teal water, warm grey chrome. Nothing outside that world.

ABSOLUTE RULES — a violation makes the image unusable:
- NO text, NO letters, NO numbers, NO words, NO signatures, NO watermarks.
  Neon signage must be reduced to abstract glowing shapes with no glyphs.
- NO faces and NO identifiable individuals. Distant anonymous silhouettes are
  allowed; anything closer is not.
- NO real-world brands, logos or trademarks, and no recognisable real vehicle,
  building or product design.
- NO imagery from any existing video game, film or TV series. Invent every
  location, every sign, every object.
- NO real cities and NO recognisable landmarks. The place must feel like the
  Florida coast without ever being a real address.

Confirm you understand, then wait for the first image request.
```

> **« NO text » reste la règle la plus utile en pratique.** Les modèles ajoutent
> spontanément des lettres déformées, et une enseigne au néon les y invite. La
> raison de fond n'est d'ailleurs pas technique : un mot dans une image
> imposerait cinq variantes, l'app étant livrée en EN/FR/ES/IT/DE.

### 5.1 Emblèmes de palier — une seule conversation, six images

Six insignes qui doivent former UNE famille. Le registre est celui du **pin's
émaillé** — émail coloré serti dans un chrome poli, comme un badge de
collection : c'est ce qui donne le lustre recherché tout en restant lisible à
64 px, là où une scène floridienne ne serait qu'une bouillie.

**Message d'amorce, après le préambule :**

```
A departure from the scenes: these SIX are objects, not places.

We are making six rank insignia for a progression ladder. They must look like
one family of collectible enamel pin badges: coloured enamel set into polished
chrome, catching a warm rim light from the upper left. Same framing, same
lighting, same bezel weight throughout — only the richness escalates from rank
1 to rank 6.

Rules for all six:
- Square, 1:1. The badge is CENTRED and alone.
- Background: PURE FLAT BLACK (#000000), absolutely uniform — no gradient, no
  vignette, no glow spilling to the edges. It gets removed programmatically.
- Roughly 10% empty margin on all four sides.
- Front-facing, symmetrical, no perspective, no cast shadow.
- Readable shrunk to 64 pixels: bold shapes, thick forms, no fine detail.

Generate rank 1 of 6 now, and nothing else.
```

**Puis un message par palier** — toujours « same family as before » :

| Palier | Prompt |
|---|---|
| 1 `tourist` | `Rank 1 — the newcomer. A plain circular chrome ring with a single crossed pair of palm fronds in pale teal enamel at its centre. Dull, unpolished chrome. The humblest badge of the six.` |
| 2 `runner` | `Rank 2 — same family. The ring is now brighter chrome, and the palm fronds are joined by three short cyan enamel speed dashes cutting across the lower left. A first hint of polish.` |
| 3 `getawayDriver` | `Rank 3 — same family. The circle becomes a hexagon in polished chrome, with a chevron of warm orange enamel pointing upward at its centre. A thin magenta enamel inlay follows the bezel.` |
| 4 `heister` | `Rank 4 — same family. A shield-shaped badge containing the hexagon from rank 3. Deep magenta and violet enamel, chrome bezel now clearly faceted and catching light on every edge.` |
| 5 `lieutenant` | `Rank 5 — same family. The same shield, now bearing a four-pointed star at its centre and two small chrome wings at its sides. Violet enamel fading into warm orange, brighter and more reflective chrome.` |
| 6 `kingpin` | `Rank 6 — same family, the most ornate. A radiant crown rising above the shield, rendered in warm gold-toned chrome, with magenta-to-violet-to-orange enamel and thin engraved rays fanning out behind it. Maximum richness — still on flat black, still readable at 64 pixels.` |

### 5.2 En-têtes de rubrique Actu — 16:9, une conversation, six images

**Amorce :**

```
Six wide banner illustrations, 16:9, one per news category. They sit behind the
top of a card in a dark feed, so:
- The composition must be QUIET: no loud focal point, no busy centre.
- The bottom third must be the darkest part of the image — text is laid over it.
- Atmosphere over subject. These are moods, not scenes with a story.

Generate banner 1 of 6 now, and nothing else.
```

| Rubrique | Prompt |
|---|---|
| `announcement` | `Banner 1 — "announcement". A wide ocean horizon at the exact moment the sun touches the water. Hot pink and orange bleeding upward into a deep indigo sky, a single column of light laid across the water, two palm silhouettes framing the far left and right edges. Empty, still, enormous.` |
| `patch` | `Banner 2 — same series. "Maintenance". An open garage bay at night, seen from outside. Chrome tools and invented mechanical parts laid out on wet concrete, lit by one cyan work lamp; everything else falls into warm shadow. No vehicle, no brand, no lettering.` |
| `event` | `Banner 3 — same series. "Event". An empty boardwalk at blue hour seen from a distance along the beach. Strings of coloured bulbs and abstract neon shapes burning above the sand, their reflection smeared across wet ground. Festive but deserted.` |
| `guide` | `Banner 4 — same series. "Guide". An empty coastal highway curving away toward a distant neon horizon, palms along the verge, the warm glow of unseen headlights spilling across the asphalt. Low camera angle, close to the road surface.` |
| `business` | `Banner 5 — same series. "Business". A row of art-deco waterfront facades at dusk, pastel walls catching the last orange light, neon signage glowing above them — reduced to pure abstract shapes, absolutely no letters or glyphs. Calm, moneyed, slightly faded.` |
| `community` | `Banner 6 — same series. "Community". A marina at night seen from above and far away: dozens of small boat lights scattered across dark water, a distant neon shoreline glowing along the top edge. Warm points of light in a large cool darkness.` |

### 5.3 Fonds d'ambiance Pro — 1:1, trois images

Ce sont les plus difficiles à obtenir : le réflexe du modèle est de composer une
belle scène, et une belle scène derrière l'interface est illisible.

**Amorce :**

```
Three full-screen background images. They sit BEHIND the entire user interface,
under translucent frosted-glass panels that blur them.

This changes everything about what makes them good:
- They must be ALMOST FEATURELESS. No subject, no object, no focal point,
  no horizon line, nothing the eye can lock onto.
- Everything out of focus, as if photographed through a rain-beaded windshield
  at night. Soft bleeding light only — this is what neon looks like when you
  are not looking at it.
- Extremely dark and extremely low contrast. The BRIGHTEST pixel in the image
  should still be dim. Think of neon light bleeding onto a black wall at night,
  seen out of focus.
- Square, 1:1.

If you find yourself drawing something recognisable, you have gone too far.
Generate background 1 of 3 now.
```

| Fond | Prompt |
|---|---|
| `magentaDrift` | `Background 1 — "magenta drift". A soft magenta glow bleeding in from the top-right corner, a deep violet wash pooling in the bottom-left, and a barely-perceptible perspective grid ghosted into the lower third — so faint it is almost invisible. Everything else is near-black #0A081A.` |
| `sunsetOverdrive` | `Background 2 — same treatment, same darkness. A warm orange glow rising from the bottom edge, a magenta haze at the top, meeting in a muddy dark band across the middle. No grid this time. Even softer and more out of focus than the first.` |
| `cyanPulse` | `Background 3 — same treatment, same darkness. A cold cyan glow pooling in the top-left, a deep violet wash across the bottom-right, and the faintest possible horizontal band of light across the middle third. The coolest and dimmest of the three.` |

**Contrôle avant de garder un fond** : le réduire à 100 px de large. S'il reste
lisible comme une « image », il est trop chargé — relancer.

---

### 5.4 Icônes d'app — 1:1, quatre images

```
Four app icons, square, full bleed.

CRITICAL: the artwork must reach all four edges. No padding, no rounded corners,
no transparent border, no drop shadow, no mockup frame. iOS applies its own
rounded mask, so anything I add here would be cropped or doubled.

Subject: a stylised compass rose in polished chrome, seen perfectly face-on,
silhouetted against a large setting sun disc that fills most of the square. Two
small palm silhouettes rise from the bottom edge, flanking the compass. The sky
above the sun goes deep #0A081A.

It must be readable at 40 pixels: three shapes maximum, thick forms, no detail,
strong contrast between the compass and the sun behind it.
No text of any kind.

Icon 1 — the primary: chrome compass with a cyan glint, magenta-to-orange sun.
```

| Icône | Prompt |
|---|---|
| primaire | *(ci-dessus)* |
| `AppIcon-MagentaDrift` | `Icon 2 — identical composition, framing and lighting, recoloured only: the compass takes a magenta glint, the sun runs violet to magenta, the palms are near-black against it.` |
| `AppIcon-SunsetOverdrive` | `Icon 3 — identical composition, framing and lighting, recoloured only: the compass takes a warm orange glint, the sun runs orange to gold, the sky behind holds a deep magenta band.` |
| `AppIcon-CyanPulse` | `Icon 4 — identical composition, framing and lighting, recoloured only: the compass glints bright cyan, the sun runs violet to cyan, and the whole image sits in blue hour rather than golden hour. The coldest of the four.` |

> **Contrainte IP absolue et sans exception** : aucune marque Rockstar dans
> l'icône ni dans l'identifiant de paquet, jamais. La règle positionnelle du
> 2026-08-08 qui autorise « GTA 6 Companion » **en suffixe du nom App Store** ne
> s'applique PAS ici. La boussole néon ne référence rien : c'est le but.

---

### 5.5 Bandeau hebdo Social — 21:9, une image

```
One ultra-wide banner, 21:9, for a weekly-highlights card.
A causeway seen from the side at night, stretching across dark water from the
left edge to the right, its lights receding into a distant magenta glow. The
left third is nearly black; the right third carries the city glow. Nothing in
the centre — a title sits there.
```

---

## 6. Post-traitement — les commandes

ImageMagick, `sips`, `potrace` et `cwebp` sont tous installés sur la machine.

### Emblèmes : noir → transparence

Aucun générateur retenu ne rend de canal alpha fiable. Pour un néon sur noir
pur, la
**luminance EST l'opacité** : cette recette préserve la lueur, ce qu'un
détourage classique détruirait.

```sh
magick raw.png -resize 512x512 \
  \( +clone -colorspace Gray -normalize \) \
  -alpha off -compose CopyOpacity -composite \
  rank-1-tourist.png
```

**Le `-normalize` n'est pas décoratif, il est indispensable.** Vérifié le
2026-08-19 sur un anneau `#26F2F2` : la luminance du cyan ne vaut que 79 % du
blanc, donc sans lui l'emblème plafonne à **alpha 0,79** — il reste
translucide même sur son trait le plus vif, et paraît délavé sur une carte de
verre. Avec, le trait ressort à alpha 1,0 en conservant exactement `#26F2F2`,
et le halo garde sa décroissance progressive (≈ 0,50 en bordure). C'est ce
dégradé d'alpha qui rend le détourage supérieur à un découpage classique, qui
lui écrête la lueur.

`-auto-level` à la place de `-normalize` ne fonctionne PAS ici — mesuré :
l'alpha reste à 0,79. Idem pour un `-channel A -auto-level` appliqué après
coup. Seul `-normalize` sur le clone gris étire réellement la plage.

Contrôle : ouvrir le PNG sur un fond clair. Si un halo gris rectangulaire
apparaît, le fond généré n'était pas un noir pur — relancer la génération, pas
la commande.

### En-têtes et bandeaux : recadrage + HEIC

```sh
magick raw.png -resize 1600x900^ -gravity center -extent 1600x900 tmp.png
sips -s format heic -s formatOptions 72 tmp.png --out news-announcement.heic
rm tmp.png
```

### Fonds d'ambiance

```sh
magick raw.png -resize 1536x1536^ -gravity center -extent 1536x1536 tmp.png
sips -s format heic -s formatOptions 60 tmp.png \
  --out NeonCompass/Resources/Assets.xcassets/Backdrops/backdrop-magentaDrift.imageset/backdrop-magentaDrift.heic
rm tmp.png
```

Les trois `imageset` existent déjà, avec leur `Contents.json` : **écraser le
`.heic` suffit**, rien d'autre à toucher. Les noms sont imposés par
`NCTheme.backdropName`, et un test échoue si l'un ne se résout plus.

`formatOptions 60` et non 72 : le fond est flou et sera reflouté par le verre.
Personne ne verra la différence, et c'est 40 % de poids en moins.

### Icônes : retirer l'alpha (obligatoire)

App Store Connect **refuse** une icône avec canal alpha, y compris un alpha
entièrement opaque.

```sh
magick raw.png -resize 1024x1024^ -gravity center -extent 1024x1024 \
  -background '#0A081A' -alpha remove -alpha off AppIcon-1024.png
```

Vérification : `magick identify -format '%[channels]\n' AppIcon-1024.png` doit
afficher `srgb`, jamais `srgba`. Recette vérifiée le 2026-08-19 (`srgba` → `srgb`).

---

## 7. Le chantier code

Petit, mais réel. Dans l'ordre.

1. ✅ **`NeonCompass/Resources/Assets.xcassets` créé, avec `AppIcon`** — fait le
   2026-08-19. Le catalogue n'a **pas** eu besoin d'être déclaré dans
   `project.yml` : il vit sous `NeonCompass/`, qui est déjà un chemin source, et
   XcodeGen range tout `.xcassets` qu'il y trouve dans la phase Resources.
   Seul `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` a dû être ajouté — sans
   lui `actool` compile le catalogue mais ne désigne aucun jeu comme étant celui
   de l'app, et l'écran d'accueil garde sa vignette grise, **sans erreur ni
   avertissement**. Vérifié dans le paquet construit : `Assets.car` présent,
   `CFBundleIconName: AppIcon` synthétisé, rendition `AppIcon-1024.png` trouvée
   par `assetutil`.

   ⚠️ **L'icône livrée est PROVISOIRE** : composée à l'ImageMagick depuis la
   palette (soleil à fentes, boussole cyan à quatre branches, grille en fuite).
   Elle existe pour que le catalogue soit vérifiable de bout en bout et que le
   simulateur cesse d'afficher une vignette vide — pas pour être publiée. Elle
   est remplacée par la sortie du §5.4.

2. ✅ **`project.yml`** — fait. `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
   nomme les trois icônes alternées *avant* qu'elles existent : vérifié, `actool`
   retire simplement un nom introuvable du `CFBundleIcons` synthétisé, sans
   erreur. Déposer les trois images sera donc le seul geste restant. Aucun
   dossier `type: folder` n'a été ajouté — voir la révision du §4.
3. ✅ **`NCTheme`** — fait. Cas `classic`, plus `isPro`, `backdropName` et
   `alternateIconName`. Défaut de `ThemeStore` passé à `.classic`,
   `theme.classic` ajouté en cinq langues.
4. ✅ **`SettingsAppearanceSection`** — fait. L'interrupteur d'icône a été
   RETIRÉ plutôt que réparé : il mentait deux fois, visant `AppIcon-Neon` qui
   n'a jamais existé, et relisant sa valeur depuis
   `UIApplication.alternateIconName`, si bien que l'activer le faisait revenir
   tout seul à l'arrêt. L'icône suit désormais le thème, synchronisée par
   `RootView` — un thème est un tout, pas deux réglages qui peuvent se
   contredire. `profile.icon.title` est sorti du catalogue, sans appelant.
5. ✅ **`RootView`** — fait. Le fond est posé en `.background`, pas dans un
   `ZStack` : la structure du `Group` a un ordre de branches chargé d'histoire
   qu'il valait mieux ne pas remanier. **Aucun chargeur maison** : le patron de
   `MapArtLoader` n'était nécessaire que pour une référence de dossier, et le
   catalogue rend `UIImage(named:)` suffisant. Vérifié au simulateur, avec un
   fond prêté à `classic` le temps de la capture : la nappe s'affiche derrière
   les cartes, le verre a enfin quelque chose à réfracter, et rien n'est
   illisible.
6. **`ProfileHeaderView`** : l'emblème de 64 pt, à côté de la capsule existante.
   *Attend les images.*
7. **`NewsCard` / `NewsDetailView`** : l'en-tête de rubrique. **Plafonner la
   colonne du fil** à 640/900 comme le fait `SocialScreen` — sans ça un bandeau
   plein cadre devrait couvrir 2 752 px sur iPad Pro 13" en paysage.
   *Attend les images.*

⚠️ **Les trois fonds en place sont PROVISOIRES**, comme l'icône : nappes floues
composées à l'ImageMagick, conformes au cahier des charges du §5.3 (sans sujet,
sans horizon, luminance maximale entre 0,10 et 0,17). Ils rendent le chemin
complet vérifiable — et remplaçables par simple écrasement du `.heic`.

**Ce qui n'est PAS vérifié, et qui reste la seule vraie inconnue** : le coût du
fond au défilement. Le verre reflouterait la nappe à chaque image, et le
simulateur amplifie fortement le coût du Liquid Glass — donc seuls des écarts
RELATIFS sont exploitables. À mesurer avec la sonde `CADisplayLink` (pire
intervalle et nombre d'intervalles > 33 ms par fenêtre nommée), avec et sans
fond, sur iPhone 17 et iPad Pro 13", en inversant l'ordre des variantes pour ne
pas imputer à l'une le coût du premier passage. Chronométrer un appel SwiftUI ne
dirait rien.

Second angle non vérifié : le rendu du fond **sous un abonnement Pro réel**. La
configuration StoreKit locale n'est attachée qu'à l'action Run d'Xcode, jamais à
`xcodebuild`, donc la ligne de commande ne peut pas acheter Pro. La capture
ci-dessus a contourné le problème en prêtant un fond à `classic` ; le chemin
`isProEntitled == true` se regarde depuis Xcode.

---

## 8. Archive IP

Exigence de CLAUDE.md. Pour chaque image conservée, consigner ici :

| Fichier | Prompt (§) | Modèle | Date | Retouches |
|---|---|---|---|---|
| *(à remplir au fil de la production)* | | | | |

Les prompts ci-dessus ne citent ni GTA, ni Rockstar, ni aucun personnage, ni
aucune œuvre existante — c'est ce que cette archive doit pouvoir démontrer.
