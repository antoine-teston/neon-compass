# Écran Codes : remettre les commandes dans l'ordre où on s'en sert

**Date** : 2026-08-10
**Statut** : validé
**Portée** : `NeonCompass/Features/Cheats/`

## Le problème

L'écran Codes empile aujourd'hui ses commandes dans cet ordre :

```
[ Tél. ][ PS ][ Xbox ][ PC ]        ← mode de saisie, segmenté
( Rechercher un code…  ) ( VI )( V ) ← recherche ET bascule de jeu
⟨ Toutes │ Joueur │ Armes │ Véhic… ⟩ ← rubriques, rangée qui défile
```

Trois défauts, dans l'ordre de gravité.

**L'ordre ne suit pas l'entonnoir.** On choisit d'abord *quel jeu*, ensuite *comment on saisit*, enfin *quoi chercher*. L'écran présente ces trois décisions dans un ordre qui n'est celui d'aucune des deux lectures possibles : ni du plus large au plus étroit, ni de l'usage le plus fréquent au plus rare.

**La bascule de jeu est cachée dans une ligne qui parle d'autre chose.** Elle a été poussée là par une économie de hauteur — le commentaire de `searchRow` la revendique : « le sélecteur tenait une ligne à lui seul pour deux chiffres romains ». L'économie était réelle ; le prix est qu'un contrôle qui change *tout le contenu de l'écran* voisine avec un champ de texte, sans hiérarchie qui dise lequel des deux compte le plus.

**Les rubriques occupent une ligne en permanence pour un geste rare.** La rangée est toujours là, qu'on filtre ou non.

## Ce qu'on fait

### 1. L'ordre de l'entonnoir, dont le premier cran monte d'un étage

```
✦ NEON COMPASS        ( VI )( V )  (⚙)   ← barre haute, hors de l'écran
─────────────────────────────────────
[ PS ][ Xbox ][ Clavier ][ Téléphone ]   ← segmenté, inchangé
( Rechercher des codes…        ) ( ☰ )   ← TextField + bouton entonnoir
```

Le `GameSwitch` **quitte l'écran pour la barre haute**, entre le mot-marque et la
molette. Il tenait une ligne entière pour deux chiffres romains ; la barre, elle,
est là de toute façon. Vérifié à la capture : tout tient sur un iPhone 17 sans
raccourcir le mot-marque, qui garde `NEON COMPASS` en entier.

Le bouton entonnoir reprend `MapFilterControls.filterToggleButton` sans le modifier
d'un point : `line.3.horizontal.decrease.circle`, cercle de verre interactif de
44 pt.

**Le bloc défile avec la liste.** Il n'est pas épinglé : des points figés en
permanence sur un écran de huit cent soixante-quatorze, pour un réglage qu'on
touche une fois par session, ne se paient pas.

#### Ce que ça change dans la barre, et pourquoi la règle cède

`AppHeaderBar` portait une règle explicite : « la molette est la seule chose admise
à droite — une barre dont le côté droit changerait d'un onglet à l'autre cesserait
d'être un repère ». Elle est révisée, et remplacée par une formulation plus juste :
**ce qui est ancré, c'est la molette, pas le vide à sa gauche.** Un écran peut
glisser un contrôle dans un emplacement `accessory` situé entre le mot-marque et
elle ; la molette ne bouge pas d'un point, donc le geste appris tient.

Ce qui reste interdit : déplacer la molette, la remplacer, ou poser dans
`accessory` autre chose qu'un contrôle qui commande l'écran surplombé. Le seul
usage aujourd'hui est l'écran Codes. Le mot-marque porte `layoutPriority(-1)` : il
est le seul élément dont la largeur soit négociable si une langue allonge ou si le
corps de texte grossit.

#### Où vit l'état, désormais

Le jeu passe de `CheatsModel` à **`AppModel`**, parce que la barre est montée par
`RootView`, au-dessus de l'écran : les deux côtés doivent le voir. `CheatsModel` le
**reçoit** — `CheatsScreen` le pousse par `onChange` — et garde ce qu'il est seul à
savoir faire : relâcher une rubrique que le nouveau jeu ne propose pas, et
recalculer.

La clé de persistance garde son ancien nom, `cheatsActiveGame`, qui ne décrit plus
où l'état vit. La renommer renverrait au défaut tous ceux qui avaient déjà choisi ;
un test le fige explicitement pour qu'un rangement bien intentionné ne le fasse pas.

**`CheatsEmptyGameView` perd sa bascule de secours.** Elle en portait une parce que
le seul exemplaire vivait dans la liste, absente dans cet état — sans elle on
restait enfermé sur le jeu à venir. La barre la porte maintenant, et la barre reste
quoi qu'affiche l'écran.

### 2. Les rubriques passent derrière l'entonnoir, dans la géométrie de la carte

`CheatsFilterBar` n'apparaît qu'au tap, sous la ligne de recherche, en **colonne
alignée à droite** — le panneau de la carte, pas la rangée de l'Actu. L'alignement
fait le travail : la colonne descend du bouton qui l'a ouverte et pointe vers lui.

**Elle se pose SUR l'écran, elle ne l'écarte pas.** Le panneau vit dans un `ZStack`
et non dans la liste : inséré dans le flux, il poussait toutes les cartes de deux
cent cinquante points vers le bas, ce qui n'est pas un menu mais un tiroir. Pendant
qu'il est ouvert, la liste **se floute légèrement** (rayon 3 — le contenu recule
d'un plan, il ne disparaît pas) et cesse de recevoir les taps ; une couche
transparente referme au premier tap à côté.

Le point d'ancrage n'est pas fixe : la ligne de recherche se mesure
(`onGeometryChange` dans un repère nommé) et le panneau se cale dessous. C'est ce
qui permet de **garder l'en-tête dans le flux**. L'ancrer au haut de l'écran aurait
obligé à épingler l'en-tête — et à payer sa hauteur en permanence, ce que la section
précédente refuse.

**Choisir referme** : c'est un menu, et un menu se ferme sur son choix. Les deux
mutations ne portent alors pas la même animation, et c'est tout le sujet — le repli
s'anime, le refiltrage de la liste non. Sans `Transaction.disablesAnimations` sur la
sélection, l'animation du repli emporterait le remplacement de la liste dans le même
passage, soit les douze images perdues de `FeedFilterBar`. Mesuré : cinq cycles
ouverture + choix + repli coûtent 6 images perdues au total, là où un refiltrage
animé en coûterait une soixantaine.

L'état d'ouverture est un `@State` de `CheatsListView`. Il survit donc à un
changement d'onglet — `RootView` garde ses écrans vivants dans un `ZStack` — et pas
à un relancement. Rien n'est écrit dans `UserDefaults` : c'est un état de vue, pas
une préférence.

**`withAnimation(.snappy)` sur la bascule, et c'est mesuré.** La première rédaction
de cette spec l'interdisait, par transport de la leçon apprise sur `FilterChip`. Le
transport était faux, et la sonde le montre : l'action d'une PUCE remplace le
contenu de la liste, donc SwiftUI anime l'apparition et la disparition de dizaines
de cartes en verre — douze images perdues par tap. Le dépliage du PANNEAU ne crée ni
ne détruit aucune carte, il les décale.

Sonde `CADisplayLink`, iPhone 17, flou compris, trois tours de six ouvertures :
**une à deux images perdues par tour, pire intervalle 33 à 34 ms**, contre zéro
perdue et 17 ms sur la fenêtre de repos. Le déploiement sec ne fait pas mieux.
Animer un flou plein écran par-dessus une pile de verre ne coûte donc rien de
mesurable ici — ce qui ne se devinait pas, d'où la mesure.

Un piège à ne pas réapprendre : la **première** fenêtre mesurée paie un coût de
premier passage de 127 à 172 ms, quelle que soit la variante qu'on y place. La
mesure initiale, qui ouvrait sur la variante animée, la condamnait pour ce motif.
Inverser l'ordre a déplacé la pointe sur l'autre variante — c'est ce qui a tranché.

### 3. Réparer ce que le repli casse

Filtre posé, panneau fermé : plus rien à l'écran ne dit sur quelle rubrique on est.
Deux réparations, indépendantes l'une de l'autre.

**Le bouton s'allume.** Rubrique choisie → `line.3.horizontal.decrease.circle.fill`
en `NCColor.neonCyan`. C'est le seul accent cyan que l'écran gagne, et il tombe dans
la seule catégorie que `CLAUDE.md` lui laisse sans discuter : « l'unique chose qu'un
écran veut faire remarquer ».

**L'en-tête de section revient toujours.** Il s'efface aujourd'hui quand une
rubrique est choisie, au motif inscrit dans le code que « la puce allumée dit déjà
laquelle » (#79, 2026-08-09). La puce n'est plus visible par défaut : la prémisse
tombe, la condition part. C'est un revirement assumé sur une décision de la semaine
précédente, pas un oubli. Le montrer toujours évite en prime qu'il clignote à chaque
ouverture du panneau — le faire dépendre de `showCategories` produirait exactement
ce défaut.

Les puces gardent le **cyan**. Aucune teinte par rubrique, aucun changement de
palette : l'Actu et les Codes emploient le même `FilterChip`, et les faire diverger
sur la couleur obligerait un lecteur à réapprendre d'un écran à l'autre ce que
signifie une capsule allumée.

### 4. Les favoris mènent quelque part, et se plafonnent

Ils existaient déjà — l'étoile orange sur chaque carte, `FavoriteCheat` en
SwiftData, et le premier alimente le widget — mais nulle part où les voir.

**UNE carte, pas une section de cartes — et la raison n'est pas d'apparence.**
Une section occupe des places dans la colonne de la liste, et `InlineAdPlacement`
distribue ses encarts sur cette colonne : des favoris en section, ce sont des
bannières entre eux. Un seul bloc n'offre aucun emplacement. **Le raccourci qu'on
se garde vers ses cinq codes ne se paie pas d'une publicité au milieu.** C'est la
raison d'être de cette forme, et ce qu'il ne faut pas défaire en la « simplifiant »
en `ForEach` de `CheatCard`.

Les favoris sont donc RETIRÉS de `displayedCheats` — un test le fige, et un second
vérifie que le filtre « Favoris » ne les rouvre pas aux annonces par la porte de
derrière.

La carte ouvre la liste, au-dessus des rubriques, et défile avec elle. Elle ne
paraît que s'il y a au moins un favori pour le jeu ET le mode actifs. Chaque ligne
tient l'effet sur une ligne coupée et son code en glyphes de quatorze points —
contre dix-huit sur une carte de liste — ce qui fait tenir cinq codes dans un bloc
sans qu'il occupe l'écran entier ; l'effet complet est à un tap dans le lecteur.

**La lueur se répartit en deux, et c'est un constat, pas une esthétique.** Une
ombre FIXE sur la carte, une respiration sur la seule étoile de l'en-tête.
`BreathingHighlight` posé sur la carte entière a rendu **l'écran entièrement noir** :
l'app vivante à 13 % de CPU, sans jamais présenter une image, bissecté à variable
unique jusqu'à ce seul modificateur. La cause tient à ce pour quoi il a été écrit —
il empile trois ombres dont une de rayon 22, et son coût a été mesuré sur des
pastilles de trente points, pas sur une carte pleine largeur de plusieurs centaines.

Le violet de `BreathingHighlight` reste réservé au jeu à venir ; l'orange ne nomme
aucun jeu, il n'entre donc pas en concurrence de sens, et il défile avec la liste,
donc il ne consomme pas en permanence l'un des trois accents lumineux que
`CLAUDE.md` autorise par écran.

**Une carte, un endroit.** Sans filtre, un favori QUITTE sa rubrique pour la carte —
l'afficher aux deux endroits serait du bruit. Le tri « favoris d'abord » à
l'intérieur des rubriques disparaît donc du cas sans filtre, où il n'a plus rien à
remonter, et **subsiste sous filtre de rubrique** : là, c'est cette rubrique qu'on
regarde, le favori y reste et mène. Sous « Favoris », la carte porte tout et les
rubriques ne rendent rien.

**Une puce `★ Favoris`**, en bas du panneau et séparée par un `FilterChipDivider`
horizontal — le séparateur a gagné un axe, le même trait dans les deux sens ne
séparant rien dans l'un des deux. En bas parce que la colonne descend du bouton, donc son dernier élément
est le plus loin de lui ; séparée parce que ce n'est pas une rubrique de plus mais
une restriction d'un autre ordre. Elle ne s'affiche pas s'il n'y a aucun favori —
une commande qui ne peut rien faire est pire qu'absente.

Le modèle passe de `selectedCategory: CheatCategory?` à un **`CheatFilter`** à trois
cas — `.none`, `.favorites`, `.category(x)`. Un booléen « favoris » à côté de la
rubrique aurait été un second état à tenir en accord, ce que ce fichier refuse déjà
pour `activeCategories`. `selectCategory(_:)` survit en façade.

**Le plafond : cinq en gratuit, sans limite en Pro.**
`toggleFavorite(_:isProEntitled:)` rend `false` quand il refuse un ajout, jamais
pour un retrait ; la vue ouvre `PaywallView` sur ce `false`. La règle vit dans le
modèle et pas dans la vue — une vue ne se teste pas. Le décompte `n/5` est masqué en
Pro, où un dénominateur ne dirait rien, et passe en magenta au plafond : les deux
règles du carnet d'épingles.

**Personne ne perd de favori.** Le plafond n'existait pas : quelqu'un peut en avoir
dix. Il bloque l'**ajout**, ne supprime rien, et le décompte affiche `10/5` en
magenta jusqu'à ce qu'on repasse sous la barre. Truquer le nombre serait pire que
l'afficher.

**Un cas connu, laissé ouvert.** Les favoris sont des identifiants globaux, la liste
est filtrée par jeu. Quelqu'un dont les cinq favoris seraient sur un jeu verrait, sur
l'autre, un plafond atteint sans aucune carte à l'écran pour l'expliquer. C'est
inatteignable tant que le jeu à venir n'a aucun code — rien n'est construit contre,
et c'est à rouvrir le jour où il en publie.

## Ce qu'on ne fait pas

**Aucun renommage vers « plateforme ».** Le type s'appelle `CheatInputMode` et c'est
délibéré : `.phone` n'est pas une plateforme mais une façon de saisir le code *dans*
le jeu, et `ps5` désignait la famille PlayStation entière, de la PS3 à la PS5, dont
les combos sont identiques. La clé héritée `cheatsActivePlatform` est encore lue une
fois au démarrage pour ne pas renvoyer au défaut quelqu'un qui avait choisi. Ni le
type, ni les clés `UserDefaults`, ni les chaînes visibles ne bougent.

**L'ouverture du panneau reste de l'état de vue** — un `@State` de
`CheatsListView`, rien dans `UserDefaults`. Contrairement au jeu, elle n'a pas à
être visible d'ailleurs que de l'écran.

**`FilterChip` et `FilterChipRow` ne bougent pas.** L'Actu garde sa rangée
horizontale, où les puces sont là en permanence et ne coûtent qu'une ligne. Les
Codes emploient un `FilterChipColumn` neuf, posé à côté — pas à la place.

**`CheatsEmptyGameView` ne bouge pas.** Elle porte sa propre bascule de jeu, parce
que la liste — et donc la bascule qui y vit — est absente dans cet état. Le
déplacement de la bascule à l'intérieur de la liste ne change rien pour elle.

## Fichiers

| Fichier | Changement |
|---|---|
| `App/AppHeaderBar.swift` | Un emplacement `accessory` entre le mot-marque et la molette ; la règle du côté droit révisée |
| `App/AppModel.swift` | `activeGame`, monté depuis `CheatsModel`, persisté sous la clé héritée |
| `App/RootView.swift` | Remplit l'emplacement pour le seul onglet Codes |
| `Features/Cheats/CheatsEmptyGameView.swift` | Perd sa bascule de secours |
| `Core/DesignSystem/FilterChip.swift` | `FilterChipColumn`, la variante en colonne pour un panneau qui se déplie |
| `Features/Cheats/CheatsFilterBar.swift` | Passe de la rangée à la colonne |
| `Features/Cheats/CheatsListView.swift` | L'essentiel : ordre des lignes, `searchAndCategories` dans un `GlassEffectContainer` unique, bouton entonnoir, `@State showCategories`, en-tête toujours affiché |
| `Features/Cheats/CheatsScreen.swift` | Deux commentaires devenus faux : celui de `CheatsEmptyGameView` (« la bascule vit dans la barre de recherche de la liste ») et le paragraphe final sur la ligne de recherche partagée |
| `Resources/Localizable.xcstrings` | Une clé neuve : `cheats.filter.toggle.a11y`, cinq langues |

## Vérification

- `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test` au vert, `LocalizationCoverageTests` compris.
- Vérifier `git status` après les tests : `xcodebuild test` réécrit parfois
  `Localizable.xcstrings` en y ajoutant des variantes à suffixe `%@`. Restaurer
  plutôt qu'emporter l'artefact.
- Capture du simulateur sur l'écran Codes, panneau fermé puis ouvert, filtre posé —
  pour vérifier de l'œil les trois choses qu'un test ne voit pas : l'ordre des
  lignes, l'entonnoir allumé, l'en-tête présent sous un filtre.

## Suite, hors de cette spec

Le mot-marque in-app (`NCWordmark`, employé par `AppHeaderBar`) doit gagner une
mention du jeu. La forme demandée à l'oral — `Neon Compass — Companion for GTA` —
est exclue par `CLAUDE.md` sur deux points : elle concatène nos mots avec la marque
dans un libellé unique, et `GTA` nu échoue au test `notANominativeName`. La forme
recevable est celle que l'app a déjà livrée sur la carte du compte à rebours : le
mot-marque intact, et **à côté** une pastille dont la valeur entière est `GTA VI`,
en `Text(verbatim:)`. Chantier distinct, spec distincte.
