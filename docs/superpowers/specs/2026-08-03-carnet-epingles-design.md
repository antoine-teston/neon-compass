# Mes épingles → le carnet de chasse

Date : 2026-08-03
Statut : validé

## Le problème

« Mes épingles » est resté au stade du prototype posé au plan 2. `PersonalPin`
porte quatre champs (`id`, `x`, `y`, `title`, `createdAt`) ; la liste est un
`List` de vingt lignes qui n'affiche qu'un titre ; l'épingle n'est pas tapable
sur la carte, donc son nom ne se lit nulle part hors VoiceOver.

Trois défauts qui ne relèvent pas du confort :

1. **`PersonalPin` n'a pas de carte.** Une épingle posée sur la carte de
   référence s'affiche aussi sur Leonida, aux mêmes coordonnées normalisées —
   donc à un endroit qui ne veut rien dire. Bug fonctionnel.
2. **La liste est une `.sheet` en largeur régulière**, alors que le CLAUDE.md
   impose un panneau latéral sur iPad.
3. **Le titre est obligatoire sans le dire.** `Button("map.personalPins.save")`
   ne fait rien quand le champ est vide : ni erreur, ni message, la feuille se
   ferme et l'épingle n'existe pas.

## Ce qu'on construit

Une épingle personnelle devient une entrée de **carnet de chasse** : un repère
posé sur la carte, nommé, annoté, et coché quand c'est fait. « Revenir ici avec
un hélico » — puis coché.

### Décisions de cadrage

| Question | Décision |
|---|---|
| À quoi ça sert | Carnet de chasse : repère + note libre + état à faire/fait |
| Rapport à la progression | Cloison étanche — coche propre à l'épingle, aucun pourcentage |
| Contenu d'une entrée | Titre + note + coche + icône parmi six fixes |
| Tap sur la carte | La fiche partagée avec les POI (bas en compact, droite en régulier) |
| Création | L'épingle est posée d'abord, nommée ensuite, dans la fiche |
| La liste | Feuille en compact / panneau en régulier ; tap = viser sur la carte |
| Gratuit / Pro | Gratuit plafonné à 20 épingles ; Pro illimité **et** synchronisé |
| Synchro | Dans le périmètre, mais chantier 2 |

**Pourquoi la cloison étanche avec la progression.** `ProgressionModel` calcule
sur des défis à total connu. Un carnet personnel n'a pas de dénominateur qui
veuille dire quelque chose : « 11 sur 11 » ne mesure que la discipline du joueur
à cocher ce qu'il a lui-même écrit. Les épingles n'entrent donc dans aucun
pourcentage, et `ProgressionItemKind` ne gagne pas de cas.

**Pourquoi une seule teinte pour toute la famille.** La palette néon appartient
aux catégories éditoriales, et la lecture « telle couleur = telle catégorie » est
ce qui rend la carte lisible. Les six icônes se distinguent par leur glyphe, sur
la même teinte `NCColor.sunsetOrange`.

## Architecture

### Le modèle

```swift
@Model
final class PersonalPin {
    var id: UUID
    var x: Double
    var y: Double
    var game: String = Game.reference.rawValue
    var title: String
    var note: String = ""
    var icon: String = PersonalPinIcon.marker.rawValue
    var isDone: Bool = false
    var createdAt: Date
    var updatedAt: Date = Date.now
    var deletedAt: Date?
}
```

Chaque champ ajouté porte une valeur par défaut : c'est ce qui laisse SwiftData
faire sa migration légère seul. Le conteneur de `NeonCompassApp` n'a pas de
`VersionedSchema` et n'a pas à en gagner un pour ce chantier.

`game` répare le bug 1. Les épingles déjà en base atterrissent sur `gtav`, la
carte de référence — celle sur laquelle l'app s'ouvre, et la seule qui ait du
contenu placé aujourd'hui.

`title` devient facultatif de fait, ce qui répare le bug 3 : l'épingle existe
avant d'avoir un nom. Une épingle sans titre s'affiche « Sans nom » dans le
carnet, jamais une chaîne vide.

`updatedAt` et `deletedAt` ne servent qu'au chantier 2, et sont posés dès le
chantier 1 pour que la synchro soit un branchement et non une migration. Le
chantier 1 les écrit (`updatedAt` à chaque commit) mais ne lit jamais
`deletedAt` : la suppression y reste physique. Le chantier 2 bascule la
suppression en pierre tombale et ajoute le filtre correspondant à toutes les
requêtes — c'est son travail, pas celui du chantier 1.

```swift
enum PersonalPinIcon: String, CaseIterable, Codable, Sendable {
    case marker, vehicle, photo, stash, danger, explore
}
```

Une valeur brute inconnue (carnet venu d'une version future, chantier 2)
retombe sur `marker` plutôt que de faire échouer le décodage : une épingle qui
disparaît est pire qu'une épingle mal illustrée.

### Le magasin

`PersonalPinStore`, `@Observable @MainActor`, dans `Core/Map/`. Calqué sur
`FoundStore` : il détient la liste, un compteur de génération pour le moteur de
carte, et il est le seul à parler à SwiftData.

```
pins(for: Game) -> [PersonalPin]
create(at: NormalizedPoint, game: Game, isProEntitled: Bool) -> PersonalPin?
update(_:title:note:)   // commit d'une session d'édition
setIcon(_:on:)  ·  toggleDone(_:)  ·  delete(_:)
totalCount  ·  isAtCap(isProEntitled: Bool)
generation
```

Trois raisons de le sortir de `MapModel` : celui-ci porte déjà le filtrage des
POI, l'état trouvé, la synchro de progression et les épingles, et c'est le
fichier qui grossit à chaque chantier ; le carnet est lu par trois vues qui n'ont
pas toutes besoin du reste ; et le chantier 2 branchera la synchro ici, comme
`FoundStore` porte la sienne.

Le plafond vit dans le magasin et non dans la vue, et le droit Pro lui est passé
en paramètre : le magasin ne connaît pas `ProEntitlementModel`, ce qui le laisse
testable sans StoreKit. `create` renvoie `nil` quand le plafond mord — un
`Optional` plutôt qu'un lancer, parce que buter sur le plafond n'est pas une
anomalie mais une réponse.

Le magasin est bâti dans `NeonCompassApp` sur `container.mainContext` et injecté
par `.environment`, exactement comme `FoundStore`. Un magasin construit par
l'écran serait reconstruit à chaque bascule d'onglet, et le carnet ouvert depuis
un autre écran verrait une autre liste.

### La sélection

`MapModel.selectedPOI: POI?` laisse la place à :

```swift
enum MapSelection: Equatable { case poi(POI), pin(PersonalPin) }
var selection: MapSelection?
```

Le panneau accueille deux natures et ne peut en montrer qu'une. Deux propriétés
facultatives côte à côte créeraient un état impossible — les deux non nulles —
qu'aucun type n'interdirait. `@Model` est déjà `Hashable`, donc
`.animation(.snappy, value:)` continue de fonctionner.

Supprimer une épingle sélectionnée doit vider `selection`, sans quoi le panneau
tient une référence à un objet effacé.

## La carte

`visiblePersonalPins` filtre par carte autant que par fenêtre.

`DroppedPinView` gagne un `isDone` et emprunte le vocabulaire déjà en place pour
les POI trouvés — `POIPinPalette.coreOpacity(found:)`, `ringWidth(found:)`,
`glowRadius(for:found:)`. Une épingle faite s'éteint exactement comme un lieu
trouvé et comme un groupe complété : même sémantique, aucun langage visuel neuf,
et le halo qui s'éteint tient la consigne des trois accents lumineux par écran à
mesure que le carnet se remplit.

**L'épingle devient tapable**, dans un `Button` posé au site d'appel et non dans
la vue : `MapPinViews` documente pourquoi — ces vues sont des valeurs
`Equatable`, et une fermeture dedans casse la conformité sous concurrence
stricte.

**Conséquence sur les zones de frappe.** `MapPinMetrics.hitSides` ne balaie
aujourd'hui que les groupes éditoriaux, sur la foi d'un commentaire affirmant que
« les épingles personnelles ne se tapent pas du tout ». Ce ne sera plus vrai : une
épingle posée près d'un lieu volerait ses taps avec ses 44 pt. Les deux familles
passent donc dans **un seul balayage**, dont on redistribue les résultats —
l'argument de non-recouvrement est géométrique, il ne connaît pas les familles.
Les propositions communautaires restent hors du balayage comme aujourd'hui :
elles sont rares et portent leur propre surface interactive.

**Viser un point.** `Coordinator.zoom(to:)` sait doubler le zoom sur un groupe ;
il lui faut un frère `focus(on:manifest:)` qui recentre sur une position à une
échelle voulue, piloté par un `focusRequest` porté en `Binding` et consommé une
fois. Sa lecture se fait **avant** le garde-fou du `contentToken` dans
`updateUIView`, sinon le retour anticipé l'avalerait. L'échelle visée ne dézoome
jamais : la plus grande entre le zoom courant et deux fois l'échelle de
couverture — sans quoi taper une ligne du carnet ferait reculer un joueur qui
venait de zoomer.

**Un interrupteur dans les filtres.** Le panneau de filtres gagne une puce « Mes
épingles » qui masque le calque entier. C'est un `Bool` à part et non un cas de
plus dans `activeCategories`, qui est un `Set<POICategory>` — y ranger une
épingle serait un mensonge de type.

## La fiche

`PersonalPinCardView`, dans `Features/Map/`, même coquille de verre que
`POIDetailView` : `.glassEffect(.regular, in: .rect(cornerRadius: 24))`, et la
même croix de 44 pt en haut à droite, qui est la seule sortie du panneau sur
iPad.

De haut en bas :

- **le titre**, un `TextField` habillé en `NCTypography.displayTitle` et
  *toujours* éditable — pas de mode édition, c'est ce qui permet à « posée puis
  nommée » de tenir sans deuxième surface. Il prend le focus à la création ;
- **la rangée des six icônes**, en cibles de 44 pt, la choisie cerclée ;
- **la note**, un `TextField(axis: .vertical)` de une à six lignes ;
- **le bouton principal**, `.glassProminent`, cyan quand c'est fait et magenta
  quand ça reste à faire — la teinte exacte de « marquer trouvé » sur un POI ;
- **« Supprimer l'épingle »**, sous confirmation.

**Le titre et la note gardent un `@State` local et ne sont commis au magasin qu'à
la perte de focus, à la validation, ou à la fermeture du panneau** — jamais à la
frappe. Le piège est mesuré et documenté dans `MapModel` : taper un caractère
dans le champ de nom coûtait une requête SwiftData plus un filtrage des 537
points. Une écriture par session d'édition, c'est aussi ce qu'il faut pour le
chantier 2 — `updatedAt` avance une fois, pas trente. L'icône et la coche passent
immédiatement par le magasin : ce sont les deux seuls champs qui changent le
dessin.

Conséquence acceptée : entre deux commits, l'étiquette d'accessibilité de
l'épingle sur la carte porte encore l'ancien titre. Elle se corrige au commit
suivant, et le titre exact reste lisible dans la fiche ouverte.

## Le carnet

`PersonalPinBookView` remplace `PersonalPinListSheet`. Feuille en compact
(`.presentationDetents([.medium, .large])`), panneau à droite en régulier — dans
la **même fente** que la fiche : ouvrir l'un ferme l'autre, jamais deux colonnes
posées sur la carte, qui est le sujet de l'écran.

- En-tête avec le décompte : « 12 / 20 » en gratuit, le seul total en Pro.
- Deux sections, « À faire » puis « Fait ».
- Chaque ligne : le glyphe de l'icône, le titre — ou « Sans nom » — la première
  ligne de la note en sourdine, une coche tapable à droite.
- Balayage pour supprimer.
- Taper la ligne referme le carnet, vise l'épingle sur la carte, ouvre sa fiche.
  C'est ce qui manque le plus aujourd'hui : rien ne ramène à une épingle dont on
  a oublié l'emplacement.
- État vide en `ContentUnavailableView` qui enseigne l'appui long, comme
  `RoutePlannerSheet` le fait pour son cas vide.

Le carnet montre les épingles **de la carte courante**, puisqu'elles lui
appartiennent désormais.

## Le plafond et Pro

Vingt épingles en gratuit, **toutes cartes confondues** — un plafond par carte en
vaudrait quarante et ne voudrait plus rien dire.

`PersonalPinStore.create` renvoie `nil` quand le plafond est atteint. L'écran
ouvre alors `PaywallView()` en feuille, comme le fait déjà `SettingsScreen`,
précédé d'un mot qui dit ce qui bloque. La ligne `paywall.feature.sync` figure
déjà dans les arguments Pro : la synchro du carnet s'y range sans en ajouter une.

**Règle de déclassement : on ne supprime jamais.** Un carnet de trente épingles
dont l'abonnement expire reste entièrement modifiable — cocher, renommer,
supprimer. Seul l'ajout est fermé. Un plafond qui effacerait des données serait
indéfendable.

## Localisation

Toutes les chaînes passent par le catalogue, dans les cinq langues, l'anglais
restant la langue de base. Les six libellés d'icône sont génériques — repère,
véhicule, photo, cache, danger, à explorer — et ne nomment aucune marque, ce que
`check-publishable` n'a pas à arbitrer ici puisque rien de ceci n'est du contenu
éditorial.

## Tests

En Swift Testing.

**`PersonalPinStoreTests`**
- le plafond bloque la 21ᵉ création en gratuit, et laisse passer en Pro ;
- une épingle créée sur une carte n'apparaît pas dans `pins(for:)` de l'autre ;
- `toggleDone` bascule et fait avancer la génération ;
- `update` avance `updatedAt` et ne le fait pas quand rien n'a changé ;
- supprimer l'épingle sélectionnée vide la sélection ;
- un carnet au-dessus du plafond reste modifiable et supprimable.

**Extension de `MapContentTokenTests`**
- changer l'icône ou la coche fait avancer `personalPinsGeneration` ;
- changer le titre seul ne le fait pas avancer.

**Extension de `MapPinShapeTests`**
- le balayage unique ne laisse aucun recouvrement entre une épingle et un groupe
  éditorial voisin.

`LocalizationCoverageTests` couvre déjà les nouvelles clés. Rappel du CLAUDE.md :
`xcodebuild test` peut réécrire `Localizable.xcstrings` — vérifier `git status`
avant de commiter.

## Découpage

**Chantier 1 — le carnet local.** Modèle, magasin, portée par carte, rendu et tap
sur la carte, balayage unique des zones de frappe, `focus(on:)`, fiche, carnet,
plafond, paywall, localisation, tests.

**Chantier 2 — la synchro Pro.** Table Supabase et RLS, révocation de privilèges
portée par la migration elle-même, entrée dans `privileges_test.sql`, protocole
`PersonalPinSyncing` dans `Core/`, réconciliation dernière-écriture-gagne sur
`updatedAt`, propagation des suppressions par `deletedAt` et bascule de la
suppression physique en pierre tombale.

**Les deux chantiers sont livrés** (2026-08-03). Trois décisions prises en cours
de route et qui n'étaient pas dans cette spec :

- **Les bornes de longueur.** `personal_pins` est la première table où le client
  écrit de la prose — `progression` ne portait qu'un identifiant, un booléen et
  une date. Sans borne, un compte y stockerait des mégaoctets, RLS l'y
  autorisant puisque ce sont ses lignes. D'où `title ≤ 200`, `note ≤ 2000`,
  `icon ≤ 32`, et `x`/`y` dans `[0, 1]`.
- **`game` porte un CHECK, `icon` non.** Ajouter une carte est un évènement
  délibéré qui s'accompagne d'une migration ; ajouter une septième icône n'est
  qu'une mise à jour d'app, et un CHECK ferait alors du serveur le goulot.
- **On ne purge jamais les pierres tombales.** Purger rouvre le danger
  classique : un appareil resté hors ligne au-delà de la fenêtre n'a pas vu la
  tombe et ressuscite l'épingle. Le coût de tout garder est d'environ deux cents
  octets par suppression.

Le carnet distant est relu à l'attache **et au retour au premier plan** : sans ce
second moment, il n'aurait été lu qu'une fois par lancement, et poser une épingle
sur l'iPad puis reprendre l'iPhone resté ouvert n'aurait rien montré.

## Hors périmètre

- Recherche et tri dans le carnet — utiles au-delà de trente épingles, du chrome
  en dessous.
- Icônes ou couleurs libres.
- Partage ou export d'un carnet.
- Toute présence des épingles dans l'écran Progression.
