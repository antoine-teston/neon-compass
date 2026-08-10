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

### 1. Trois lignes, dans l'ordre de l'entonnoir

```
              ( VI )( V )           ← GameSwitch, seule, centrée
[ Tél. ][ PS ][ Xbox ][ PC ]        ← segmenté, inchangé
( Rechercher un code…      ) ( ☰ )  ← TextField + bouton entonnoir
```

Le `GameSwitch` est **centré**. Sur la carte il vit en bas à droite, parce que la
carte occupe le fond et qu'un contrôle centré masquerait ce qu'on regarde ; cette
contrainte n'existe pas au-dessus d'une liste. Centrée, et seule sur sa ligne, la
bascule tient lieu de titre à un écran qui n'en a pas — `RootView` n'accorde de
barre de navigation à aucun écran d'onglet.

Le bouton entonnoir reprend `MapFilterControls.filterToggleButton` sans le modifier
d'un point : `line.3.horizontal.decrease.circle`, cercle de verre interactif de
44 pt.

**Le bloc défile avec la liste**, comme aujourd'hui. Il n'est pas épinglé : cent
quarante-cinq points figés en permanence sur un écran de huit cent soixante-quatorze,
pour un réglage qu'on touche une fois par session, ne se paient pas.

### 2. Les rubriques passent derrière l'entonnoir, dans la géométrie de la carte

`CheatsFilterBar` n'apparaît qu'au tap, sous la ligne de recherche, en **colonne
alignée à droite** — le panneau de la carte, pas la rangée de l'Actu. L'alignement
fait le travail : la colonne descend du bouton qui l'a ouverte et pointe vers lui.
Elle coûte la hauteur de six puces, ce qu'on ne consent que parce qu'elle est
transitoire.

Un seul `GlassEffectContainer` englobe la ligne de recherche ET la colonne. Un
seul, et c'est tout l'intérêt : le verre ne se fond qu'entre éléments d'un même
conteneur, donc les puces naissent du bouton au lieu d'apparaître à côté. La carte
en emploie deux et n'obtient pour cette raison qu'un fondu, jamais la fusion.

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

Sonde `CADisplayLink`, iPhone 17, trois tours de six allers-retours : **une à deux
images perdues par tour, pire intervalle 33 à 47 ms**, contre zéro perdue et 17 ms
sur la fenêtre de repos. Le déploiement sec ne fait pas mieux.

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

## Ce qu'on ne fait pas

**Aucun renommage vers « plateforme ».** Le type s'appelle `CheatInputMode` et c'est
délibéré : `.phone` n'est pas une plateforme mais une façon de saisir le code *dans*
le jeu, et `ps5` désignait la famille PlayStation entière, de la PS3 à la PS5, dont
les combos sont identiques. La clé héritée `cheatsActivePlatform` est encore lue une
fois au démarrage pour ne pas renvoyer au défaut quelqu'un qui avait choisi. Ni le
type, ni les clés `UserDefaults`, ni les chaînes visibles ne bougent.

**`CheatsModel` ne bouge pas.** L'ouverture du panneau est de l'état de vue.

**`FilterChip` et `FilterChipRow` ne bougent pas.** L'Actu garde sa rangée
horizontale, où les puces sont là en permanence et ne coûtent qu'une ligne. Les
Codes emploient un `FilterChipColumn` neuf, posé à côté — pas à la place.

**`CheatsEmptyGameView` ne bouge pas.** Elle porte sa propre bascule de jeu, parce
que la liste — et donc la bascule qui y vit — est absente dans cet état. Le
déplacement de la bascule à l'intérieur de la liste ne change rien pour elle.

## Fichiers

| Fichier | Changement |
|---|---|
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
