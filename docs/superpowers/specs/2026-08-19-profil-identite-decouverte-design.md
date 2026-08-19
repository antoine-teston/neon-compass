# Profil : carte Identité, Découverte condensée, retrait des trophées

Design validé le 2026-08-19. Remplace la structure d'entête décidée le
2026-08-04 (`2026-08-04-profil-connecte-design.md`) sur deux points, et en
confirme un troisième.

## Ce qui change, et ce qui ne change pas

La décision structurante du 04/08 — **deux jauges, jamais une** — tient. Ce
qui change est la place qu'elles occupent et le vocabulaire qui les nomme.

| | avant | après |
|---|---|---|
| Dénomination visible | deux échelles nommées, deux registres | une seule, sur l'exploration |
| Registre | nautique (`Balise`, `Phare`) | ascension criminelle (`Coursier`, `Caïd`) |
| Progression par jeu | une carte par jeu ayant des défis | deux anneaux, les deux jeux toujours |
| Trophées | une carte, vide en permanence | retirés |
| Hauteur de l'écran | ~1 400 pt | ~600 pt |

**Ce qui ne change pas** : l'XP reste écrite serveur et ne récompense jamais
l'exploration — la faire dépendre d'un compteur local la rendrait falsifiable,
et elle fonde le classement public. `profiles.level` reste une colonne générée,
et aucun seuil XP n'est déclaré côté client.

## 1. La dénomination

`ExplorerGrade` devient **`StreetRank`**, six paliers indexés sur le nombre de
lieux cochés. Seuils inchangés — ils sont calibrés sur les 537 POI du socle, et
rien dans ce chantier ne justifie de les rouvrir.

| lieux | EN | FR | ES | IT | DE |
|---|---|---|---|---|---|
| 0 | Tourist | Touriste | Turista | Turista | Tourist |
| 10 | Runner | Coursier | Recadero | Manovale | Laufbursche |
| 40 | Getaway Driver | Chauffeur | Conductor de fuga | Autista in fuga | Fluchtfahrer |
| 100 | Heister | Braqueur | Atracador | Rapinatore | Räuber |
| 250 | Lieutenant | Lieutenant | Lugarteniente | Luogotenente | Unterboss |
| 500 | Kingpin | Caïd | Capo | Boss | Pate |

**Pourquoi ce registre et pas un autre.** Trois échelles ont été écrites dans
les cinq langues avant de choisir, et c'est le passage en ES/IT/DE qui a
tranché : une échelle de repérage (`Scout` → `Spotter`) donne deux
quasi-synonymes indistinguables dans trois langues sur cinq
(`Explorador`/`Localizador`, `Kundschafter`/`Späher`), et une échelle
nocturne produit le palier terne `Habitué`/`Asiduo` et des libellés de 18
caractères en capitales. L'ascension criminelle a un mot idiomatique par palier
dans chaque langue.

**Garde-fou IP.** Ces dix-huit libellés sont du vocabulaire de genre inventé
par nous. Aucun n'est tiré de la fiction Rockstar — ni personnage, ni gang, ni
ville — et aucun n'est une marque. C'est de la prose que nous écrivons :
l'exception nominative de `nominative-fields.mjs` ne s'y applique pas, et n'a
pas à s'y appliquer.

`ContributorGrade` sort du projet : le fichier, ses cinq clés, et son test. La
ligne contribution ne porte plus que des chiffres — `240 XP · Rang 87 · 2 en
attente`. Deux échelles nommées dans deux registres étrangers l'un à l'autre, à
dix points d'écart sur la même carte, n'était explicable par rien.

## 2. La carte Identité

```
┌────────────────────────────────────────┐
│  NEON-ELECTRIC-29               [PRO]  │
│                                        │
│  ╭──────────╮                          │
│  │ BRAQUEUR │              137 lieux   │
│  ╰──────────╯                          │
│  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░            │
│  113 avant « Lieutenant »              │
│  ──────────────────────────────────    │
│  ◆ 240 XP · Rang 87 · 2 en attente     │
└────────────────────────────────────────┘
```

La dénomination devient une **pastille de verre teinté** et non du texte
capitalisé : c'est un insigne de rang, il doit se lire comme tel. Elle reprend
l'idiome que `FilterChip` et `CompactTabBar` ont déjà — verre teinté plutôt
qu'un aplat posé derrière du verre, ce qui reviendrait à payer le verre sans le
voir.

**La pastille s'affiche déconnecté**, parce que l'exploration est locale. C'est
un gain net et non un effet de bord : aujourd'hui un déconnecté lit son grade
en texte gris atténué ; demain il a son insigne dès le premier lieu coché. La
règle unique de `ProfileHeaderState` est respectée — *tout ce qui est chiffré
suit `profile != nil`* ne parle que de l'XP et du rang serveur.

Modernisation UI, sur ce qu'iOS 26 apporte et rien de plus :

- **Verre teinté** pour la pastille (`.glassEffect(.regular.tint(…), in: .capsule)`).
- **`Gauge`** avec `.gaugeStyle(.accessoryLinearCapacity)` à la place de
  `ProgressView(value:)` : un `Gauge` porte sémantiquement une valeur dans une
  plage, ce qu'une barre de progression indéterminée-ou-non ne fait pas, et
  VoiceOver en tire une valeur au lieu d'un pourcentage nu.
- **`.contentTransition(.numericText(value:))`** sur le compteur de lieux :
  cocher un POI fait rouler le chiffre plutôt que le remplacer sèchement.
- **`.symbolEffect(.bounce, value:)`** sur le glyphe de la pastille, déclenché
  par le changement de palier — le seul moment où l'app a quelque chose à
  célébrer.
- **`GlassEffectContainer`** englobant la carte et la pastille, faute de quoi
  deux surfaces de verre voisines ne se fondent pas l'une dans l'autre.

## 3. La carte Découverte, et la feuille Défis

```
┌────────────── DÉCOUVERTE ──────────────┐
│      ╭─────╮            ╭─────╮        │
│      │  —  │            │ 68% │        │
│      ╰─────╯            ╰─────╯        │
│         VI                 V           │
│      12 lieux          412 / 604       │
│                                        │
│  15 défis                           ›  │
└────────────────────────────────────────┘
```

**Les deux jeux toujours présents.** `gamesWithChallenges` disparaît : c'est ce
filtre qui rendait GTA VI invisible, puisque les quinze collections publiées
sont toutes GTA V. L'ordre est celui de `Game.allCases` — le jeu à venir
d'abord, la référence ensuite — le même que `GameSwitch`, pour la raison que
`GameSwitch` documente déjà : deux contrôles d'apparence identique dont l'ordre
diffèrerait seraient pires que n'importe lequel des deux ordres.

**Un tiret, jamais 0 %,** quand aucun total n'est connu. `ProgressRing` prend
donc un `Double?` : à `nil` il ne trace pas d'arc et affiche `—`. Afficher 0 %
dirait « tu n'as rien trouvé » là où la vérité est « on ne sait pas encore
combien il y en a ». C'était déjà la règle du modèle ; elle devient visible.

**Correction que ce chantier rend obligatoire.** `POI` n'a pas de champ `game` :
le jeu se déduit du magasin d'où le POI vient, et `ProgressionSection` fusionne
les deux tableaux avant de les passer au modèle. Un POI GTA VI a
`collection: nil` par défaut, donc il ne compte dans aucun jeu — « 12 lieux »
côté VI est inatteignable en l'état. `ProgressionModel` reçoit désormais
`poisByGame: [Game: [POI]]`. L'appelant construisait déjà les deux magasins
séparément : c'est la fusion prématurée qui perdait l'information, pas le
modèle qui manquait d'un champ.

**Le détail passe en feuille.** `ChallengesSheet` porte son propre
`NavigationStack`, donc un titre et une fermeture — un écran d'onglet n'en a
pas, et un `ToolbarItem` posé sur lui ne s'afficherait nulle part. Un dépliage
sur place aurait ramené les 1 100 pt dans un `ScrollView` déjà long, et son état
se perd à chaque bascule d'onglet.

## 4. Le retrait des trophées

Ce n'est pas une fonctionnalité retirée mais une ébauche jamais finie :
`content/trophies/` n'existe pas, `trophy.schema.json` non plus, `content-cli`
n'en sait rien, et la carte affiche « Aucun trophée publié » en permanence
depuis son écriture.

Partent : `Trophy.swift`, `TrophyProgress.swift`, `extension Trophy: ContentItem`,
quatre membres de `ProgressionModel`, la branche trophée de `reconcile`, la
carte et la ligne de `ProgressionListView`, les deux clés `progress.trophies.*`,
`TrophyTests.swift`, et le `ContentStore<Trophy>` de `loadModel` — soit **un
aller-retour réseau de moins à chaque ouverture du Profil**.

Deux points demandent de la précaution :

- **`ProgressionItemKind.trophy` peut partir sans migration.**
  `SupabaseProgressionSync.fetchAll` ignore déjà les `kind` inconnus avec une
  ligne de journal. La contrainte `check (kind in ('poi','trophy'))` reste en
  base : les lignes existantes restent valides, on cesse simplement d'en
  écrire. Aucune migration SQL dans ce chantier.
- **Retirer `TrophyProgress.self` du `ModelContainer` touche le schéma
  SwiftData**, et le conteneur est construit en `try!`. Aucune ligne ne peut
  exister en pratique, mais l'entité est présente dans le magasin des
  installations existantes. À prouver et non à supposer.

  **Prouvé, et par un test plutôt que par une installation.** La méthode prévue
  ici — installer la version d'avant, lancer, installer la nouvelle par-dessus —
  demande de piloter le simulateur à la main, ne laisse aucune trace et ne se
  rejoue pas. `SchemaMigrationTests` fait la même transition sur un fichier
  temporaire : le magasin est écrit avec le schéma d'avant, `TrophyProgress`
  incluse, refermé, puis réouvert avec celui d'après. Le `try` du test est le
  `try!` de l'app. Ce qui rend ce test honnête est l'assertion de sa prémisse —
  une ligne de trophée relue dans le magasin d'avant — sans laquelle il passerait
  aussi bien si l'entité n'avait jamais atteint le fichier.

  Ce que dit Core Data au passage vaut d'être noté, parce que c'est exactement ce
  qu'on cherchait à savoir : `Persistent History (1) has to be truncated due to
  the following entities being removed: (TrophyProgress)`. Journalisé en `error`,
  suivi de trois avertissements sur l'historique — et **récupéré**, pas levé.
  L'ouverture réussit et la progression locale survit, ce que le test vérifie en
  relisant le `FoundEntry` écrit par le build d'avant.

  Le sens inverse est couvert aussi — réinstaller la version précédente depuis
  TestFlight ne doit pas planter davantage. `TrophyProgress` est donc
  redéclarée dans la cible de test, et nulle part ailleurs — c'est le nom de
  classe dont SwiftData tire le nom d'entité, donc cette déclaration suffit à reproduire le magasin d'une
  installation existante sans réintroduire le modèle dans l'app.

## 5. Localisation et tests

Le catalogue maigrit : ~10 clés ajoutées (`streetRank`, Découverte, feuille),
13 retirées (`explorerGrade`, `contributorGrade`, `trophies`).
`LocalizationCoverageTests` est le filet.

Tests neufs ou étendus :

- `StreetRankTests` — les six seuils, les bornes exactes (9/10, 499/500), pas
  de barre au dernier palier, repli sur un compte négatif.
- `ProfileHeaderStateTests` — la pastille existe déconnecté ; la ligne XP
  n'existe que `profile != nil` ; `xp == 0` donne l'invitation et non « 0 XP ».
- `DiscoveryStateTests` — les deux jeux toujours là ; total inconnu → tiret et
  compte absolu ; **le compte par jeu vient des POI du jeu et non des défis**,
  qui est le test que le tableau fusionné faisait échouer ; et
  `theDisplayedFractionIsExactlyTheRingsPercentage`, l'invariant né de la passe
  à l'écran (§6).
- `SchemaMigrationTests` — le retrait de `TrophyProgress` du `ModelContainer`,
  dans les deux sens, sur un vrai fichier. Détaillé au §4.
- `ProgressionReconciliationTests` — les trois tests trophée sont remplacés par
  un seul, qui vérifie ce que le chemin du Profil ne faisait pas : appliquer la
  progression POI distante.

## 6. Vérification à l'écran

Faite le 2026-08-19 sur iPhone 17 (iOS 26.5) et iPad Pro 13 M5, en pilotant le
simulateur. Ce que les 705 tests ne peuvent pas voir : la mise en page, et la
cohérence de deux nombres affichés côte à côte.

Confirmé sur iPhone : la pastille de palier, la jauge, les deux anneaux avec le
tiret sur le volet à venir, la feuille Défis. Puis douze lieux cochés sur la
carte, **sans relancer l'app** — le Profil suit en direct, le palier passe de
Touriste à Coursier, le symbole de la pastille de marcheur à coureur, la jauge
s'amorce, « 28 avant Chauffeur » se recalcule, l'anneau V passe à 4 %. C'est le
chemin `onChange(of: foundStore.foundIDs)` que `DiscoverySection` documente comme
né d'un bug, et il tient.

**Un défaut trouvé, et seulement là.** Sur iPad, avec 204 lieux cochés, l'anneau
de la carte de référence annonçait 51 % pendant que le compte juste dessous
disait « 204 / 267 » — soit 76 %. Les deux nombres étaient justes séparément et
faux ensemble : 204 compte **tous** les lieux cochés du jeu, 267 ne totalise que
les défis à total connu. Posés de part et d'autre d'une barre de fraction, ils se
contredisaient.

Le numérateur devient donc `foundInChallenges`, la somme des trouvés sur les
mêmes défis que le dénominateur — donc exactement le quotient dont l'anneau
affiche le pourcentage : « 137 / 267 » sous 51 %. Le compte d'exploration
(204 lieux) ne disparaît pas, il reste sur la carte Identité, où rien ne le
divise par autre chose.

`theDisplayedFractionIsExactlyTheRingsPercentage` fixe l'invariant, et il a été
vu échouer sur l'ancien comportement (`204 == 25`) avant d'être cru. Le défaut
n'était pas seulement absent des tests : `aTotallessChallengeDoesNotDiluteItsNeighbours` portait la contradiction dans sa propre fixture — 32 lieux cochés
en face d'un `progress` de 25/50 — sans que rien ne l'affirme ni ne s'en plaigne.

## Hors périmètre, signalé

- Le widget lit `overallProgress` (VI sinon V) et continuera d'afficher un seul
  nombre. L'aligner sur deux anneaux est un autre chantier.
- Le reconnaisseur d'appui long de la carte reste armé pendant un placement
  (constaté en fusionnant #114). Sans rapport avec le Profil.
