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

> **Pour produire, suivre `2026-08-20-feuille-de-prompts-midjourney.md`** : les
> mêmes prompts, dans l'ordre de génération, sans le raisonnement. Cette
> section-ci porte le *pourquoi* ; la feuille porte ce qui se colle. Les deux
> bougent ensemble.


### 5.0 Direction visuelle — élargie le 2026-08-20

**Deux versions abandonnées, pour deux raisons différentes.**

La première demandait du synthwave abstrait — grilles en perspective, contours
néon, schémas éclatés. Mauvaise cible : on obtient une grille vectorielle quand
on demande une grille vectorielle.

La seconde, qui la corrigeait, est tombée dans l'excès inverse : **tout se
passait au bord de la nuit, tout brillait au néon.** C'est la carte postale
Miami Vice, et c'est un seul registre sur six. L'ambiance recherchée tient
autant au **soleil de midi qui écrase une aire de parking** qu'à une enseigne
qui bave sur l'asphalte mouillé — et c'est même la banalité américaine en plein
jour qui la caractérise le mieux, parce que personne ne la met sur une affiche.

#### Les six registres

Chaque image en choisit **un seul**, et le lot doit les couvrir tous.

| Registre | Lumière | Ce qu'on y trouve |
|---|---|---|
| **Midi écrasant** | Soleil vertical, blanc, sans pitié. Ombres courtes et dures, voile de chaleur. | Aires de parking fendillées, centres commerciaux de bord de route, stations-service, grillages, chariots abandonnés, palmiers poussiéreux. |
| **Marécage** | Ciel de plomb avant l'orage, lumière plate, sans ombre. | Cyprès, mangrove, chaussée sur pilotis, eau stagnante, poteaux télégraphiques, cabanes de tôle, hydroglisseurs. |
| **Heure dorée** | Soleil rasant, orange épais, ombres longues. | Front de mer, planches, lampadaires pas encore allumés, silhouettes lointaines, reflets sur le chrome. |
| **Heure bleue** | Ciel indigo, premières lumières artificielles — sodium orange, pas néon. | Mâts d'éclairage, parkings de stade, marinas, stations-service isolées, phares. |
| **Nuit néon** | Noir, enseignes, asphalte mouillé qui garde la couleur. | Façades art déco, palmiers en contre-jour, flaques colorées. *Un registre parmi six, plus le registre par défaut.* |
| **Aube** | Rose-gris, brume basse, calme plat, aucune ombre marquée. | Panneaux d'affichage vides, autoroutes désertes, ponts, ports, grues. |

#### Ce qui rend le registre juste, quel que soit l'éclairage

- **La banalité assumée.** Un laverie, une bretelle d'autoroute, un mur de
  parpaings. Le sujet n'est jamais héroïque ; c'est le traitement qui l'est.
- **L'usure.** Peinture délavée, rouille, herbe dans les fissures, plastique
  cuit par le soleil. Rien de neuf, rien de propre.
- **L'échelle humaine sans humains.** Des lieux faits pour des gens, vides ou
  presque. C'est ce qui donne le calme un peu inquiétant.
- **Le grain.** 35 mm, halation dans les hautes lumières, léger flare.

#### Un changement de parti pris : photographique, plus aérographié

La version précédente imposait « PAINTERLY and airbrushed, never photographic ».
**On inverse pour les scènes.** Le registre recherché est celui d'une photo de
repérage cinéma : réaliste, contrastée, étalonnée chaud. C'est aussi ce que
Midjourney fait de mieux avec `--raw`. L'aérographe reste, mais seulement pour
les **objets** — emblèmes et icônes, §5.2 et §5.5 — où il est le bon outil.

#### Sur la filiation

L'ambiance ne s'obtient pas en citant un jeu : les modèles commerciaux dégradent
ou refusent sur un nom de franchise, et CLAUDE.md l'interdit de toute façon.
Elle s'obtient en nommant les **sources réelles**, publiques et qui
n'appartiennent à personne — la photographie de Michael Mann, les repérages
floridiens, les cartes postales touristiques, l'Amérique de bord de route de
Stephen Shore et William Eggleston. C'est plus précis qu'un nom de marque, donc
ça rend mieux.

#### La palette

Les illustrations ont une gamme plus large que l'interface. **La palette de
l'INTERFACE ne bouge pas** ; les images gagnent les neutres que la lumière
exige — sable, crème, turquoise profond, gris chrome, ocre, vert marécage — et
les cinq teintes de la charte doivent y rester présentes sans forcément dominer
en plein jour.

#### La contrainte qui n'a pas bougé : ça doit rester sombre

L'interface est à `#0A081A`. Une image de midi est par nature lumineuse, et
c'est la tension réelle de ce lot. **Elle se résout au post-traitement, pas au
prompt** : on génère la scène avec sa vraie lumière, puis on l'assombrit et on
lui pose un voile dégradé, en mesurant le résultat (§6). Demander « dark » à un
prompt de plein midi ne produit pas une scène sombre, il produit une scène
sale.

---

### 5.1 Comment Midjourney tient une série

**Le document supposait une conversation qui se souvient. Midjourney n'en a
pas** : chaque prompt est indépendant et doit être autonome. La cohérence passe
par trois leviers, pas par « same style as before ».

| Levier | Usage |
|---|---|
| `--sref <url>` | **Le principal.** Générer une image d'ancrage, la publier, coller son URL dans toutes les suivantes. Verrouille lumière, grain, étalonnage. |
| `--profile` / `--p` | Un moodboard réutilisable, si le lot devait s'agrandir. Inutile pour 20 images. |
| `--seed` | Fige l'aléa pour comparer deux variantes d'un même prompt. Outil de test, pas de série. |

**Hygiène des paramètres** (documentation Midjourney) : toujours **à la fin** du
prompt, un **espace** avant les tirets, et **aucune ponctuation** à l'intérieur
— d'où les listes `--no` séparées par des espaces et non par des virgules.

**Paramètres retenus pour ce lot :**

- `--raw` — mode brut, moins d'interprétation esthétique maison. Indispensable
  pour le rendu photographique des scènes.
- `--s 50` — stylisation basse. On veut la scène décrite, pas la scène rêvée.
- `--c 0` — aucun chaos, pour que la série reste une série.
- `--draft` — moitié moins cher en GPU. **Tout le dégrossissage se fait ainsi**,
  on ne repasse en qualité pleine que sur la composition retenue.
- `--no ...` — la liste d'exclusion, identique partout.

**Le bloc à répéter dans chaque prompt de scène** (remplace le préambule) :

```
35mm film still, cinematic location scouting photograph, fine grain, halation,
subtle anamorphic flare, weathered and lived-in, no people in frame
--raw --s 50 --c 0 --no text letters words numbers signage logos brands faces
people crowds watermark signature frame border
```

> **`--no text` reste la règle la plus utile.** Les modèles ajoutent
> spontanément des lettres déformées, et une enseigne les y invite. La raison de
> fond n'est pas technique : un mot dans une image imposerait cinq variantes,
> l'app étant livrée en EN/FR/ES/IT/DE. Tout panneau doit rester **vierge**.

---

### 5.2 Emblèmes de palier — six objets, pas six lieux

Registre à part : ce sont des **pin's émaillés**, chrome poli et émail coloré,
lisibles à 64 px. Pas de `--raw` ici, et une stylisation plus haute.

**Ancrage** — générer d'abord celui-ci, garder son URL pour `--sref` :

```
collectible enamel pin badge, polished chrome bezel with coloured enamel inlay,
warm rim light from upper left, centred and alone, front facing, perfectly
symmetrical, no perspective, no cast shadow, bold thick shapes readable when
tiny, product photograph on a pure flat black background
:: a plain circular chrome ring enclosing a single pair of crossed palm fronds
in pale teal enamel, dull unpolished chrome, the humblest badge of a set
--ar 1:1 --s 250 --c 0 --no text letters words numbers logos faces people
background gradient vignette glow reflections scenery
```

Puis les cinq suivants, **avec `--sref <url de l'ancrage>` ajouté** :

| Palier | Sujet (le reste du prompt est identique) |
|---|---|
| 1 `tourist` | *(l'ancrage ci-dessus)* |
| 2 `runner` | `brighter chrome ring enclosing crossed palm fronds with three short cyan enamel speed dashes across the lower left, a first hint of polish` |
| 3 `getawayDriver` | `polished chrome hexagon enclosing an upward chevron in warm orange enamel, thin magenta enamel inlay following the bezel` |
| 4 `heister` | `faceted chrome shield enclosing a hexagon, deep magenta and violet enamel, every edge catching light` |
| 5 `lieutenant` | `chrome shield bearing a four pointed star with two small chrome wings at its sides, violet enamel fading into warm orange, highly reflective` |
| 6 `kingpin` | `ornate chrome shield with a radiant crown rising above it in warm gold toned chrome, magenta to violet to orange enamel, thin engraved rays fanning out behind` |

**Le fond noir plat est une exigence technique**, pas esthétique : le détourage
du §6 en dépend. `--no background gradient vignette glow` est ce qui l'obtient.

---

### 5.3 En-têtes de rubrique Actu — 16:9, six registres différents

**C'est ici que l'élargissement se voit.** Six rubriques, six lumières, une
seule au néon. Chaque prompt est autonome ; ajouter `--sref <url>` d'une image
retenue si la série part dans tous les sens.

Le tiers inférieur doit rester le plus sombre — le titre s'y pose.

| Rubrique | Registre | Prompt |
|---|---|---|
| `announcement` | Aube | `empty coastal highway at dawn beneath a colossal blank billboard on rusted steel stilts seen from below, pink grey pre sunrise sky, low mist over flat calm water, distant palms, nothing written anywhere, monumental and silent --ar 16:9` |
| `patch` | Midi écrasant | `open roll up door of a roadside repair garage at high noon, blinding white sunlight on cracked concrete outside, cool dark cluttered interior with a hydraulic lift and scattered tools, heat shimmer, oil stains, chain link fence --ar 16:9` |
| `event` | Heure bleue | `floodlit stadium parking lot at blue hour, tall light masts blazing over rows of parked cars, orange sodium pools on wet asphalt, deep indigo sky, distant anonymous silhouettes far away --ar 16:9` |
| `guide` | Marécage | `lonely junction on a raised swamp causeway under flat pewter storm light, bald cypress and mangrove, standing black water, leaning telegraph poles, blank unmarked direction signs, no horizon glow --ar 16:9` |
| `business` | Midi écrasant | `vast empty strip mall parking lot at high noon, faded painted lines on cracked asphalt, abandoned shopping carts, blank white signage boards with nothing on them, dusty palm row, heat shimmer, utterly deserted --ar 16:9` |
| `community` | Heure dorée | `beachfront boardwalk at golden hour, long raking shadows across weathered planks, warm orange light through palm fronds, distant anonymous figures far down the promenade, lens flare, chrome railings --ar 16:9` |

Coller le bloc de style du §5.1 à la suite de chacun.

**Contrôle avant de garder** : l'image doit survivre à l'assombrissement du §6.
Une scène de midi correctement exposée descend bien ; une scène déjà grise
devient de la boue.

---

### 5.4 Fonds d'ambiance Pro — 1:1, trois images

Les plus difficiles du lot : le réflexe du modèle est de composer une belle
scène, et une belle scène derrière l'interface est illisible. Ce sont des
**lieux vus hors mise au point**, pas des dégradés — mais si flous qu'aucun
sujet ne se lit.

Le bloc de style du §5.1 ne s'applique PAS ici (pas de grain, pas de netteté) :

```
extreme bokeh, completely out of focus, no subject, no focal point, no horizon,
soft bleeding light only, very dark and very low contrast, the brightest pixel
still dim, near black
--ar 1:1 --raw --s 40 --c 0 --no text letters sharp focus detail subject
horizon people faces objects
```

| Fond | Sujet, entièrement défocalisé |
|---|---|
| `magentaDrift` | `the underside of a concrete overpass at night in heavy rain, distant magenta signage bleeding through the downpour, deep violet shadow pooling below` |
| `sunsetOverdrive` | `the last ten minutes of dusk over an open swamp, dying warm orange along the bottom edge fading up into deep indigo, cypress shapes dissolved into nothing` |
| `cyanPulse` | `an empty swimming pool lit from underwater at night, cold cyan light rippling upward, deep violet darkness all around` |

**Contrôle** : réduire à 100 px de large. S'il reste lisible comme une
« image », c'est trop chargé — relancer. La mesure de luminance du §6 fait foi.

---

### 5.5 Icônes d'app — 1:1, quatre images

Registre graphique, pas photographique. Lisible à 40 px : trois formes, pas
plus.

```
flat vector app icon, bold graphic emblem, thick clean strokes, high contrast,
centred symmetrical composition, full bleed artwork reaching all four edges
:: a stylised chrome compass rose seen perfectly face on, silhouetted against a
large setting sun disc, two palm silhouettes flanking it low in the frame
--ar 1:1 --s 300 --c 0 --no text letters numbers photorealism detail clutter
rounded corners padding border frame drop shadow mockup transparency
```

| Icône | Variante de couleur (le reste identique) |
|---|---|
| primaire | `cyan compass, magenta to orange sun, near black #0A081A sky` |
| `AppIcon-MagentaDrift` | `magenta compass, violet to magenta sun, violet palms` |
| `AppIcon-SunsetOverdrive` | `warm orange compass, orange to yellow sun, deep magenta palms` |
| `AppIcon-CyanPulse` | `bright cyan compass, violet to cyan sun, pale cyan palms — the coldest of the four` |

**Le plein bord est critique** : iOS applique son propre masque arrondi, donc
tout coin arrondi, marge ou ombre portée présent dans l'image serait rogné ou
doublé. D'où la liste `--no` très fournie.

> **Contrainte IP absolue et sans exception** : aucune marque Rockstar dans
> l'icône ni dans l'identifiant de paquet, jamais. La règle positionnelle du
> 2026-08-08 qui autorise « GTA 6 Companion » **en suffixe du nom App Store** ne
> s'étend pas ici.

---

### 5.6 Bandeau hebdo Social — 21:9, une image

```
elevated night view along a coastal causeway, chains of warm sodium street
lights receding into the distance, dark water on both sides, distant city glow
low on the right, deep indigo sky
--ar 21:9
```

Plus le bloc de style du §5.1. **Composition imposée** : le tiers gauche
presque noir, le tiers droit porte la lueur de la ville, **rien au centre** —
un titre s'y pose.

---

### 5.7 Sujets libres : personnages, véhicules, bâtiments — années 90

Ajouté le 2026-08-20. **Ce n'est pas un lot livrable** : aucun emplacement de
l'app n'attend ces images aujourd'hui, et le §4 reste à 20 fichiers. C'est une
trousse de prompts, à ouvrir quand un écran en demandera.

#### La ligne à ne pas franchir, et pourquoi elle passe là

Un **style artistique n'est pas protégeable**. Peindre à la manière de, éclairer
à la manière de, cadrer à la manière de : rien de tout cela n'est réservé. Ce
qui l'est, ce sont les **œuvres précises** — un personnage nommé, une jaquette
donnée, un logo, une carrosserie déposée.

D'où la règle de travail : **on ne s'inspire pas du jeu, on remonte à ce dont le
jeu s'inspire.** Miami et Los Angeles des années 90, le cinéma criminel de
l'époque, la photographie de bord de route américaine, l'architecture art déco
défraîchie. Ces sources sont publiques et n'appartiennent à personne. Le
résultat est du même monde sans être de la même main — et c'est plus précis à
formuler, donc mieux rendu.

Trois interdits concrets, qui découlent tous du même risque : **qu'on nous prenne
pour l'officiel.** C'est le vrai danger de cette app, celui que la règle
positionnelle du 2026-08-08 traite déjà pour le nom.

1. **Ne pas imiter la signature graphique des jaquettes.** Le contour noir épais,
   l'aplat vectoriel, la composition en vignettes : c'est l'élément le plus
   reconnaissable, celui qui relève de la présentation commerciale et non du
   style. On garde notre traitement photographique du §5.0.
2. **Aucun véhicule réel.** Les carrosseries sont des dessins déposés. On invente
   des silhouettes d'époque, sans le moindre écusson.
3. **Aucun personnage existant**, du jeu comme d'ailleurs, et aucun visage de
   personne réelle.

#### Une règle du §5.1 qui change ici

Le bloc de style interdit « NO faces and NO identifiable individuals ». **Pour
cette famille seulement, les visages redeviennent possibles**, à condition
qu'ils soient inventés. Le garde-fou se déplace dans la liste `--no` et dans le
choix du cadrage : de dos, de loin, à contre-jour, ou de trois quarts sous un
couvre-chef. Un portrait frontal net d'un visage réaliste n'apporte rien à
l'app et concentre tout le risque.

#### Le bloc de style « années 90 »

À coller à la suite de chaque prompt de cette section, en remplacement de celui
du §5.1 :

```
1990s period photograph, shot on expired 35mm Kodak Gold, warm faded colour,
slight halation, visible grain, sun bleached, humid Florida light, lived in and
worn, cinematic location scouting frame
--raw --s 60 --c 0 --no text letters words numbers signage logos brands
badges emblems watermark signature smartphones flatscreens LED modern cars
recent architecture
```

> La seconde moitié de la liste `--no` est un **anti-anachronisme**, et c'est
> elle qui fait le plus de travail : le réflexe du modèle est de glisser un
> téléphone moderne ou un phare à LED dans une scène d'époque, ce qui détruit le
> registre plus sûrement qu'une erreur de couleur.

#### Personnages — archétypes anonymes

Des rôles, pas des individus. Le cadrage fait la moitié du travail.

| Sujet | Prompt (+ bloc de style) |
|---|---|
| Le mécano | `invented anonymous auto mechanic in oil stained coveralls seen from behind wiping hands on a rag, standing in the mouth of a garage bay, harsh noon light outside, face not visible --ar 4:5` |
| Le voiturier | `invented young valet in a plain burgundy jacket leaning against a stucco wall at dusk, shot from across the street at distance, backlit by a porte cochere lamp, silhouette reading clearly --ar 4:5` |
| Le patron de bateau | `weathered invented boat captain in a faded cap and open shirt on a marina pontoon at golden hour, three quarter view from behind, face shadowed under the cap brim --ar 4:5` |
| Le vendeur de rue | `invented street vendor pushing a battered pastel cart along a cracked sidewalk at high noon, seen from far down the block, heat shimmer, palms --ar 16:9` |
| Le vigile | `invented night security guard silhouetted in the lit doorway of a strip mall unit, seen from the empty parking lot at blue hour, entirely backlit --ar 16:9` |
| Le skateur | `invented skater mid roll along a beachfront promenade at golden hour, motion blur, shot from low and behind, long shadow, no face visible --ar 16:9` |

#### Véhicules — silhouettes inventées

**Un seul mot compte : `invented`.** Sans lui le modèle produit une voiture
réelle reconnaissable, ce qui est exactement l'écueil.

| Sujet | Prompt (+ bloc de style) |
|---|---|
| Coupé | `invented boxy 1990s American two door coupe with pop up headlights, faded red paint, chrome bumpers, parked alone under a street lamp at night on wet asphalt, no badges or emblems anywhere, blank licence plate --ar 3:2` |
| Berline fatiguée | `invented beige 1990s four door sedan with mismatched panels and a sagging rear suspension, parked on cracked concrete at high noon, no badges, blank plate --ar 3:2` |
| Break familial | `invented wood panelled 1990s station wagon covered in salt haze, parked at a deserted beach lot at dawn, roof rack, no badges, blank plate --ar 3:2` |
| Pick-up de marais | `invented mud caked 1990s pick up truck with a snorkel and roll bar, parked on a dirt levee beside black swamp water under flat storm light, no badges --ar 3:2` |
| Vedette rapide | `invented low slung 1990s offshore powerboat in faded teal and white, moored at a wooden pontoon at golden hour, no lettering on the hull --ar 3:2` |
| Moto | `invented 1990s cruiser motorcycle with chrome forks, parked in an empty motel lot at blue hour, sodium light overhead, no badges or tank graphics --ar 3:2` |

#### Bâtiments — l'Amérique de bord de route

C'est la famille la plus sûre du lot : ces typologies sont génériques et
publiques. Aucun monument, aucune adresse réelle.

| Sujet | Prompt (+ bloc de style) |
|---|---|
| Motel | `invented two storey roadside motel with a horseshoe plan around a cracked pool, faded turquoise doors, blank sign board on a tall pole, high noon, no lettering --ar 16:9` |
| Laverie | `invented corner laundromat at night, fluorescent interior glowing through a plate glass window onto an empty sidewalk, banks of machines inside, nobody there --ar 16:9` |
| Immeuble art déco | `invented four storey art deco apartment block in faded pastel pink and mint, rounded corner, glass block stairwell, air conditioning units in every window, golden hour --ar 4:5` |
| Station-service | `invented isolated gas station under a wide flat canopy on a swamp highway at blue hour, fluorescent tubes buzzing, blank price board, cypress treeline behind --ar 16:9` |
| Centre commercial | `invented low strip mall with a continuous concrete awning and blank signage boards above each unit, vast empty parking lot, dusty palm row, high noon heat shimmer --ar 16:9` |
| Cabane de marais | `invented corrugated tin fishing shack raised on stilts over black water, airboat tied beneath, cypress and hanging moss, flat pewter storm light --ar 16:9` |

#### Contrôle avant de garder une image de cette section

Trois questions, dans cet ordre :

1. **Un écusson, un logo, une lettre quelque part ?** Relancer. C'est l'échec le
   plus fréquent et le plus disqualifiant.
2. **Un anachronisme ?** Écran plat, phare à LED, téléphone moderne, jante
   récente. Relancer en renforçant le `--no`.
3. **Est-ce que ça ressemble à quelque chose de précis** — une voiture qu'on
   pourrait nommer, un visage qu'on croit reconnaître, une jaquette connue ?
   Relancer. C'est la seule des trois qui demande un jugement, et c'est celle
   qui compte.

Toute image conservée passe au §8 comme les autres, avec son Job ID.

---

### 5.8 La DA dans l'app — l'image d'ancrage et ses emplacements

Ajouté le 2026-08-20, à la demande : non pas un écran précis, mais **que le
parti pris visuel se sente partout dans l'app**.

#### D'abord une correction : la ligne du §5.7 était trop large

Le §5.7 dit « ne pas imiter la signature graphique des jaquettes ». Formulé
ainsi c'est excessif, et il faut être exact parce que la nuance décide de ce
qu'on s'autorise.

**La technique n'est pas réservée.** L'aplat vectoriel, le contour noir épais,
le trait net et la couleur franche sont un procédé d'illustration banal, employé
par d'innombrables marques ; personne ne le possède, et l'imiter n'est pas une
faute.

Ce qui pose un risque, c'est **l'impression d'ensemble** — la combinaison qui
fait qu'un regard distrait croit voir l'officiel : la grille de vignettes de
personnages, leurs poses et leur attitude, la palette rose-et-bleu associée à ce
traitement, et bien sûr tout ce qui approche le logotype. C'est la
*présentation commerciale* qui est en jeu, pas le style.

→ **On peut utiliser le procédé ; on évite le gestalt.** Concrètement : une
illustration vectorielle contrastée, oui ; une planche de portraits en vignettes
dans une palette rose et bleu, non.

#### Le vrai levier de cohérence : une image d'ancrage

Une direction artistique ne se tient pas par une liste d'adjectifs répétée dans
vingt prompts — elle dérive à la troisième image. Elle se tient par **une seule
image, générée en premier, dont l'URL sert de `--sref` à toutes les autres.**
C'est le mécanisme le plus efficace de Midjourney, et il transforme la charte en
objet plutôt qu'en intention.

**Prompt de l'ancrage** — à générer avant tout le reste, en qualité pleine, et à
itérer jusqu'à ce qu'elle plaise vraiment ; tout le lot en héritera :

```
wet empty street at dusk in a humid subtropical American city, a low roadside
motel on the left with faded turquoise doors and a blank unlit sign board, an
invented boxy 1990s coupe parked under a street lamp, tall palms in silhouette,
storm clouds breaking over a magenta and orange sky, chrome and puddles holding
the colour, cracked asphalt, power lines, nobody in frame
35mm film still, cinematic location scouting photograph, fine grain, halation,
subtle anamorphic flare, weathered and lived in
--ar 16:9 --raw --s 60 --c 0 --no text letters words numbers signage logos
brands badges emblems watermark signature people faces smartphones LED
```

Elle est composée pour contenir **toute la charte d'un coup** : le ciel porte
magenta et orange, le lampadaire et l'enseigne portent le cyan et le violet,
l'asphalte porte le presque-noir, et le chrome, le béton et le sable portent
les neutres chauds. Un `--sref` sur cette image transmet donc l'étalonnage
entier, pas seulement une ambiance.

**Ensuite** : `--sref <url de l'ancrage>` sur les scènes du §5.3, du §5.6 et du
§5.7. Les emblèmes (§5.2) et les icônes (§5.5) en sont **exclus** — ce sont des
objets graphiques, l'ancrage photographique les abîmerait.

#### Où la DA peut se poser, sans se battre avec le verre

CLAUDE.md pose la règle : Liquid Glass pour tout le chrome, l'ambiance
**uniquement dans la couche de contenu**, et au plus trois accents lumineux par
écran. Ça exclut d'emblée la barre d'onglets, les barres d'outils et les
feuilles. Reste ceci, vérifié dans le code le 2026-08-20 :

| Emplacement | État aujourd'hui | Valeur |
|---|---|---|
| **`PaywallView`** | **Câblé le 2026-08-20** — bannière 150 pt en tête, gabarit provisoire en place | Le meilleur emplacement du lot : le seul écran où une image se paie littéralement. |
| **`DisclaimerView`** | **Câblé le 2026-08-20** — bannière 140 pt, repli sur le symbole `sun.horizon.fill` | Premier écran vu de l'app, c'est là que le ton se donne. |
| Fonds d'ambiance Pro | **Livré** (§7) | La DA est déjà derrière tout le verre, pour les abonnés. |
| En-têtes d'actu | Planifié (§5.3) | Six images, six registres : c'est le lot qui fera le plus pour la cohérence perçue. |
| Emblèmes de palier | Planifié (§5.2) | Petits mais vus souvent. |
| `ContentUnavailableView` | Deux usages seulement (`RoutePlannerSheet`, `PersonalPinBookView`) | Faible rendement — deux écrans rarement atteints. À laisser de côté. |

#### Ce qui est câblé, et ce qu'il reste à faire

Les deux emplacements sont **livrés avec des gabarits provisoires** (2026-08-20).
Déposer l'image définitive est désormais le seul geste : remplacer le `.heic`
dans `Assets.xcassets/Artwork/`, sans toucher au code.

- `Core/DesignSystem/NCArtwork.swift` — l'énumération des emplacements et la vue
  `NCArtworkBanner`. L'absence d'image est un état normal : l'emplacement
  disparaît, ou retombe sur son repli, sans trou dans l'écran.
- `PaywallView` a gagné un `ScrollView` au passage. Il en avait besoin
  indépendamment de la bannière : neuf lignes de fonctionnalités, un titre, un
  sous-titre et deux boutons dans une pile fixe débordaient déjà en silence.
- `NCArtworkTests` — trois tests, dont un qui **mesure la luminance moyenne** de
  chaque illustration et refuse au-delà de 0,35. C'est le filet de l'étape
  d'étalonnage du §6, vérifié capable d'échouer (0,853 sur une image brute).

#### Ce qui ferait rater la charte

- **Trop d'images.** Le parti pris de CLAUDE.md est la retenue ; une app où
  chaque écran porte une illustration ressemble à une brochure, pas à un outil.
  Quatre ou cinq emplacements bien choisis suffisent à ce qu'on « sente » la DA.
- **Des images claires.** L'interface est à `#0A081A`. Tout ce qui n'est pas
  étalonné selon le §6 casse la continuité au lieu de la créer.
- **Une image par écran, sans parenté.** C'est exactement ce que l'ancrage
  empêche — et sans lui, vingt images générées séparément forment vingt DA.

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

### En-têtes et bandeaux : recadrage, assombrissement, voile, HEIC

**L'étape d'assombrissement n'est pas cosmétique.** Depuis l'élargissement du
§5.0, deux des six en-têtes sont des scènes de plein midi : correctement
exposées, elles sont éclatantes, et posées telles quelles sur une interface à
`#0A081A` elles la crèvent. On génère la scène avec sa vraie lumière — c'est ce
qui la rend juste — puis on l'étalonne ici.

```sh
# 1. recadrage
magick raw.png -resize 1600x900^ -gravity center -extent 1600x900 \
       -modulate 58,115,100 base.png

# 2. voile dégradé, transparent en haut, presque opaque en bas
magick -size 1600x900 gradient:'rgba(10,8,26,0)-rgba(10,8,26,0.92)' scrim.png
magick base.png scrim.png -compose over -composite tmp.png

# 3. HEIC
sips -s format heic -s formatOptions 72 tmp.png --out news-announcement.heic
rm base.png scrim.png tmp.png
```

`-modulate 58,115,100` = luminosité à 58 %, saturation à 115 %. La saturation
remonte parce qu'assombrir désature : sans elle la scène vire au gris.

**Le contrôle, à passer sur chaque en-tête :**

```sh
magick banner.png -alpha off -colorspace Gray \
       -format 'ensemble  max=%[fx:maxima] moy=%[fx:mean]\n' info:
magick banner.png -alpha off -gravity south -crop 1600x300+0+0 +repage \
       -colorspace Gray -format 'tiers bas max=%[fx:maxima] moy=%[fx:mean]\n' info:
```

> **`-alpha off` n'est pas décoratif, et l'oublier fait mentir la mesure.**
> `%[fx:mean]` moyenne *toutes* les couches, alpha compris — et l'étape du voile
> ajoute justement une couche alpha. Sans lui, une image opaque et sombre est
> rapportée à `max=1` avec une moyenne exactement à mi-chemin entre sa vraie
> valeur et 1. Constaté le 2026-08-20 en fabriquant les gabarits : moy=0,095
> lue comme 0,55, soit un contrôle qui refuse une image parfaitement bonne — et
> qui, dans l'autre sens, en accepterait une mauvaise.

Vérification croisée du seuil : le test `noArtworkIsBrightEnoughToBlowOutTheInterface`
mesure la même chose côté app, par réduction à un pixel via `CGContext`. Sur une
image volontairement non étalonnée, les deux mesures donnent 0,8535 et 0,85272 —
elles se valident l'une l'autre.

Seuils, mesurés le 2026-08-20 sur une scène de midi volontairement éclatante
(max 0,97 / moy 0,85 avant traitement) :

| Zone | Après recette | Seuil à respecter |
|---|---|---|
| Ensemble | max 0,72 · moy 0,28 | max ≤ 0,75 |
| Tiers bas | max 0,32 · **moy 0,16** | moy ≤ 0,20 |

C'est la moyenne du tiers bas qui décide : c'est là que le titre blanc se pose.
Au-dessus de 0,20, remonter l'opacité du voile plutôt que rabaisser
`-modulate`, sinon toute l'image devient boueuse.

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

| Fichier | Prompt (§) | Modèle | Job ID | Date | Retouches |
|---|---|---|---|---|---|
| *(à remplir au fil de la production)* | | | | | |

**Relever le Job ID de Midjourney** pour chaque image conservée : il est
horodaté chez l'éditeur et rattaché au compte, ce qui en fait une preuve de
provenance autrement plus solide qu'une ligne de tableau que nous écrivons
nous-mêmes. Pour les images produites localement (FLUX klein-4B), c'est la
graine (`--seed`) et le nom exact du modèle qui jouent ce rôle.

Les prompts ci-dessus ne citent ni GTA, ni Rockstar, ni aucun personnage, ni
aucune œuvre existante — c'est ce que cette archive doit pouvoir démontrer.
