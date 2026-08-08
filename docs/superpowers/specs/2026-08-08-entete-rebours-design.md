# Barre d'en-tête et compte à rebours de sortie

**Décidé le 8 août 2026.** Deux ajouts d'interface : une barre haute portant le
mot-marque sur tous les onglets sauf la Carte, et un compte à rebours jusqu'à la
sortie du jeu en tête du fil Actu.

## Le mot-marque

Le projet n'avait aucun logo — pas d'`Assets.xcassets`, pas même une icône. Le
mot-marque est donc **dessiné en SwiftUI** (`NCWordmark`) plutôt qu'importé : une
rose des vents à quatre branches (`NCCompassRose`, un `Shape`) suivie de
« NEON COMPASS » en capitales interlettrées.

Pourquoi un tracé et pas un SF Symbol : le seul glyphe système qui ressemble à
une boussole est celui de Safari. Emprunter l'icône d'une autre app pour porter
notre identité serait un mauvais calcul, et la contrainte IP dit la même chose
autrement — ce qui nous identifie doit être original. Ce tracé pourra servir de
germe à la vraie icône.

Le nom passe par `Text(verbatim:)`, **hors catalogue de chaînes**. C'est
l'exception assumée à la règle « aucun littéral en dur » : un nom propre ne se
traduit pas, et l'inscrire obligerait `LocalizationCoverageTests` à garder cinq
copies identiques d'un mot qui ne changera jamais.

## La barre

`AppHeaderBar` est le miroir de `CompactTabBar` : une capsule de verre qui flotte
au-dessus du contenu, dimensionnée à ce qu'elle porte, alignée à gauche. Elle est
volontairement **vide à droite** — tout ce qu'on serait tenté d'y poser
(réglages, recherche, bascule de jeu) vit déjà dans le contenu de l'écran
concerné, et une barre qui change d'un onglet à l'autre cesse d'être un repère.

**La Carte est le seul écran sans barre** (`AppTab.showsHeaderBar`). Elle se joue
en plein écran — on y zoome, on y glisse, on y pose des épingles — et une capsule
flottante y mangerait la vue au moment précis où l'on veut le plus de place.

**L'accroche est dans `RootView.tabContent(for:)`**, pas dans `compactLayout` :
les deux dispositions passent par cette fonction, donc la barre n'existe qu'une
fois. Posée dans le `ZStack` du compact, il aurait fallu la dupliquer côté
`TabView`, où elle aurait en plus recouvert la barre latérale.

La réserve haute (`NCLayout.headerBarClearance`) est appliquée par `RootView`
lui-même, en `safeAreaPadding` — et non par chaque écran, comme l'est encore la
réserve basse. `safeAreaPadding` et non `padding` : c'est ce qui fait descendre
le contenu des `ScrollView` **sans** décoller les fonds, qui ignorent la zone
sûre. Conséquence : un écran d'onglet futur hérite de la réserve sans rien avoir
à savoir.

## Le rebours

`GameRelease` porte la date — **19 novembre 2026, minuit local** — et les trois
phases que l'app en tire : `countdown`, `released`, `gone`.

**La date est une constante compilée, pas une clé d'`app_config`.** L'option
serveur a été examinée puis écartée : le cache d'`app_config` n'a pas de TTL,
donc une correction n'agirait qu'au prochain lancement à froid, et un report de
sortie s'annonce des mois à l'avance — une soumission a tout le temps de passer
la review.

Minuit **local** : une sortie mondiale se vit à l'heure du joueur, pas à celle
d'un fuseau que personne n'habite. Le `Calendar` est un paramètre, ce qui rend
les bornes testables sans dépendre de l'horloge ni du fuseau de la machine.

À la seconde exacte de la sortie on est **sorti** — un rebours affichant
« 0j 0h 0m 0s » serait le seul moment où il mentirait. La carte bascule alors sur
un état de sortie en magenta, puis **se retire d'elle-même après sept jours**
plutôt que de rester en tête du fil indéfiniment.

`ReleaseCountdownCard` vit en tête du fil, avant les articles **et avant l'état
vide** : quand rien n'est publié, c'est la seule chose que l'écran a à dire.
En tête du fil et non dans la barre : c'est l'information la plus attendue de
l'app, elle mérite des chiffres qu'on lit de loin. Le prix — elle disparaît au
premier geste de défilement — est le bon : on ne consulte pas un rebours en
continu, on vient le voir.

**Le libellé ne nomme jamais le jeu.** La marque reste interdite dans la prose
que nous écrivons ; la décision du même jour sur le nom App Store
(`2026-08-08-nom-app-usage-nominatif-design.md`) n'a ouvert que les métadonnées
de boutique. Sur l'onglet Actu d'une app compagnon, « Sortie dans » ne désigne de
toute façon rien d'autre.

## Le refactor au passage

`NCCountdownDigits` et `ncNeonGlow` sont extraits d'`OnlineEventCountdown`, qui
en était le seul porteur. Le découpage jours/heures/minutes/secondes, les
chiffres à largeur fixe, les deux ombres du halo et la bascule au magenta le
dernier jour existaient en un exemplaire ; deux copies auraient divergé au
premier réglage. Les clés `social.event.countdown.long/short` deviennent
`countdown.long/short` — elles ne relèvent plus du domaine « social ».

Le libellé, lui, **reste chez chaque appelant** : c'est la seule chose qui
distingue les deux usages — une fenêtre qui se referme n'est pas un jeu qui sort.

## Vérification

`GameReleaseTests` couvre les six bornes de phase, `AppTabTests` vérifie dans les
deux sens que la Carte est le seul onglet sans barre. Vu au simulateur : iPhone
17 Pro (barre posée, rebours lisible, aucun contenu masqué), Carte (aucune barre,
recherche à sa place), iPad Pro 13 pouces (barre sous la barre d'onglets système,
sans collision).

## Hors périmètre

Pas de catalogue d'assets ni d'icône d'app, pas de date pilotée par le serveur,
pas de rebours ailleurs que sur Actu, pas de notification le jour J.
