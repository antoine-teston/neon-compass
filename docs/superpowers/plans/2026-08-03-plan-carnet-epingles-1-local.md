# Carnet d'épingles — chantier 1 (local) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformer « Mes épingles » — un prototype à quatre champs, une liste muette et des épingles non tapables — en un carnet de chasse : repère nommé, annoté, illustré, coché, portant sa carte, plafonné à vingt en gratuit.

**Architecture:** Un magasin `PersonalPinStore` dans `Core/Map/` prend la propriété des épingles à `MapModel` et devient le seul à parler à SwiftData, sur le modèle de `FoundStore`. La sélection de la carte devient une somme `MapSelection` pour que le panneau existant accueille indifféremment un POI et une épingle. Deux vues nouvelles — la fiche `PersonalPinCardView` et le carnet `PersonalPinBookView` — se posent dans la fente de panneau déjà en place.

**Tech Stack:** Swift 6 concurrence stricte, SwiftUI, SwiftData, Observation (`@Observable`), Swift Testing, XcodeGen.

## Global Constraints

- **iOS/iPadOS 26+**, universel iPhone + iPad. L'iPad est de première classe : jamais une feuille là où la largeur régulière veut un panneau latéral.
- **Liquid Glass pour tout le chrome** (`.glassEffect()` dans des `GlassEffectContainer`) ; le synthwave vit dans la couche de contenu. Halo sur trois accents au maximum par écran.
- **Swift 6, concurrence stricte. SwiftUI seulement** — pas d'UIKit hors de ce qui existe déjà dans `MapScrollView`.
- **Aucune chaîne en dur.** Tout passe par `Localizable.xcstrings`, en cinq langues : `en` (base), `fr`, `es`, `it`, `de`.
- **Aucun écran d'onglet n'a de `NavigationStack`.** Un `ToolbarItem` posé sur un écran d'onglet ne s'affiche nulle part, sans erreur. Ce qui doit vivre dans une barre passe par un bouton dans le contenu, ou par une feuille — qui, elle, peut avoir son `NavigationStack`.
- **Swift Testing** (`import Testing`), jamais XCTest, pour tout test nouveau.
- **`xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`** en y ajoutant des variantes à suffixe `%@` sans traduction, ce qui fait tomber `LocalizationCoverageTests`. Vérifier `git status` avant chaque commit ; restaurer avec `git checkout -- NeonCompass/Resources/Localizable.xcstrings` plutôt qu'emporter l'artefact.
- Simulateurs : `iPhone 17` (iOS 26.5) et `iPad Pro 13-inch (M5)`.
- Spec de référence : `docs/superpowers/specs/2026-08-03-carnet-epingles-design.md`.

Commandes de référence :

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests
```

---

## Structure des fichiers

**Créés**

| Fichier | Responsabilité |
|---|---|
| `NeonCompass/Core/Map/PersonalPinIcon.swift` | Les six icônes, leur glyphe SF Symbol et leur clé de libellé. |
| `NeonCompass/Core/Map/PersonalPinStore.swift` | Propriétaire unique des épingles : disque, cache, génération, plafond. |
| `NeonCompass/Features/Map/PersonalPinCardView.swift` | La fiche d'une épingle — créer, nommer, annoter, illustrer, cocher, supprimer. |
| `NeonCompass/Features/Map/PersonalPinBookView.swift` | Le carnet : sections à faire/fait, décompte, tap pour viser. |
| `NeonCompassTests/Map/PersonalPinStoreTests.swift` | Le plafond, la portée par carte, les générations, `updatedAt`. |

**Modifiés**

| Fichier | Changement |
|---|---|
| `NeonCompass/Core/Map/PersonalPin.swift` | Six champs de plus, tous avec valeur par défaut. |
| `NeonCompass/Core/Map/MapPinViews.swift` | `DroppedPinView` gagne `isDone` ; `hitSides` reste inchangé mais son commentaire ment et doit être corrigé. |
| `NeonCompass/Core/Map/MapScrollView.swift` | Épingles tapables, balayage unique des zones de frappe, `focus(on:)`, `focusRequest`. |
| `NeonCompass/Features/Map/MapModel.swift` | Perd la propriété des épingles ; `selectedPOI` devient `selection`. |
| `NeonCompass/Features/Map/MapScreen.swift` | Panneau à deux natures, création sans alerte, carnet adaptatif, plafond. |
| `NeonCompass/Features/Map/MapFilterControls.swift` | Puce « Mes épingles », bouton du carnet re-glyphé. |
| `NeonCompass/App/NeonCompassApp.swift` | Construit et injecte `PersonalPinStore`. |
| `NeonCompass/Resources/Localizable.xcstrings` | ~22 clés nouvelles, 3 retirées. |
| `NeonCompassTests/Map/MapContentTokenTests.swift` | Suit le déménagement des épingles vers le magasin. |

**Supprimé**

| Fichier | Raison |
|---|---|
| `NeonCompass/Features/Map/PersonalPinListSheet.swift` | Remplacé par `PersonalPinBookView`. |

---

## Task 1 : Le modèle et les six icônes

**Files:**
- Create: `NeonCompass/Core/Map/PersonalPinIcon.swift`
- Modify: `NeonCompass/Core/Map/PersonalPin.swift`
- Test: `NeonCompassTests/Map/PersonalPinStoreTests.swift` (créé ici, complété en tâche 2)

**Interfaces:**
- Consomme : `Game` (`NeonCompass/Core/Game.swift`), dont `Game.reference.rawValue == "gtav"`.
- Produit :
  - `enum PersonalPinIcon: String, CaseIterable, Codable, Sendable` — cas `marker, vehicle, photo, stash, danger, explore` ; `var symbol: String` ; `var labelKey: String.LocalizationValue` ; `static func from(rawValue:) -> PersonalPinIcon` (repli sur `.marker`).
  - `PersonalPin` avec `game: String`, `note: String`, `icon: String`, `isDone: Bool`, `updatedAt: Date`, `deletedAt: Date?`, et `var iconValue: PersonalPinIcon`.

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `NeonCompassTests/Map/PersonalPinStoreTests.swift` :

```swift
import Foundation
import SwiftData
import Testing
@testable import NeonCompass

@MainActor
struct PersonalPinStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Icônes

    /// Une valeur brute inconnue vient d'un carnet écrit par une version plus
    /// récente (chantier 2, synchro). Une épingle mal illustrée reste une
    /// épingle ; une épingle qui refuse de se décoder disparaît.
    @Test func anUnknownIconFallsBackToTheMarker() {
        #expect(PersonalPinIcon.from(rawValue: "helicopter") == .marker)
        #expect(PersonalPinIcon.from(rawValue: "") == .marker)
    }

    /// Chaque icône porte un glyphe DISTINCT : c'est le glyphe qui distingue les
    /// épingles entre elles, puisqu'elles partagent toutes la même teinte.
    @Test func everyIconHasItsOwnSymbol() {
        let symbols = PersonalPinIcon.allCases.map(\.symbol)
        #expect(Set(symbols).count == PersonalPinIcon.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    /// Le défaut du modèle répare le bug de fuite entre cartes : une épingle
    /// écrite sans carte appartient à la carte de référence, celle sur laquelle
    /// l'app s'ouvre.
    @Test func aPinDefaultsToTheReferenceMap() {
        let pin = PersonalPin(x: 0.5, y: 0.5, title: "Planque")
        #expect(pin.game == Game.reference.rawValue)
        #expect(pin.iconValue == .marker)
        #expect(pin.isDone == false)
        #expect(pin.note.isEmpty)
        #expect(pin.deletedAt == nil)
    }
}
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | tail -20
```

Attendu : ÉCHEC de compilation — `cannot find 'PersonalPinIcon' in scope`.

- [ ] **Step 3 : Écrire `PersonalPinIcon`**

Créer `NeonCompass/Core/Map/PersonalPinIcon.swift` :

```swift
import Foundation

/// Ce qu'une épingle personnelle représente, en six choix fixes.
///
/// Six et non un catalogue libre : la palette néon appartient aux catégories
/// éditoriales, et la lecture « telle couleur = telle catégorie » est ce qui
/// rend la carte lisible. Les épingles personnelles partagent donc toutes la
/// même teinte, et c'est le GLYPHE qui les distingue — même raisonnement que
/// `POIPinPalette`, où le symbole porte l'information et la couleur la renforce.
///
/// Les libellés sont génériques et ne nomment aucune marque : le CLAUDE.md
/// interdit les marques déposées partout où nous rédigeons nous-mêmes.
enum PersonalPinIcon: String, CaseIterable, Codable, Sendable {
    case marker, vehicle, photo, stash, danger, explore

    var symbol: String {
        switch self {
        case .marker: "mappin"
        case .vehicle: "car.fill"
        case .photo: "camera.fill"
        case .stash: "shippingbox.fill"
        case .danger: "exclamationmark.triangle.fill"
        case .explore: "questionmark"
        }
    }

    var labelKey: String.LocalizationValue {
        switch self {
        case .marker: "map.pins.icon.marker"
        case .vehicle: "map.pins.icon.vehicle"
        case .photo: "map.pins.icon.photo"
        case .stash: "map.pins.icon.stash"
        case .danger: "map.pins.icon.danger"
        case .explore: "map.pins.icon.explore"
        }
    }

    /// Décodage TOLÉRANT, à l'inverse de `Game`.
    ///
    /// La raison de la différence : `Game` décode du contenu que nous
    /// produisons, où une valeur illisible est un défaut de publication qu'il
    /// vaut mieux entendre. Ici la valeur vient du disque du joueur, et le
    /// chantier 2 la fera venir d'un autre appareil, possiblement plus récent.
    /// Refuser de décoder y ferait disparaître une épingle ; se rabattre sur le
    /// repère générique n'en abîme que l'illustration.
    static func from(rawValue: String) -> PersonalPinIcon {
        PersonalPinIcon(rawValue: rawValue) ?? .marker
    }
}
```

- [ ] **Step 4 : Étendre `PersonalPin`**

Remplacer intégralement `NeonCompass/Core/Map/PersonalPin.swift` :

```swift
import Foundation
import SwiftData

/// Une entrée du carnet de chasse — marqueur strictement local, distinct de la
/// contribution communautaire (spec §5), qui requiert un compte.
///
/// **Chaque champ ajouté porte une valeur par défaut**, et c'est ce qui laisse
/// SwiftData faire sa migration légère seul : le conteneur de `NeonCompassApp`
/// n'a pas de `VersionedSchema` et n'a pas à en gagner un pour ce chantier.
///
/// `game` répare une fuite : sans lui, une épingle posée sur la carte de
/// référence s'affichait AUSSI sur Leonida, aux mêmes coordonnées normalisées —
/// donc à un endroit qui ne veut rien dire. Les épingles déjà en base
/// atterrissent sur la carte de référence, celle sur laquelle l'app s'ouvre.
///
/// `updatedAt` et `deletedAt` ne servent qu'au chantier 2 (synchro Pro) et sont
/// posés dès maintenant pour que la synchro soit un branchement et non une
/// migration. Le chantier 1 ÉCRIT `updatedAt` mais ne lit jamais `deletedAt` :
/// la suppression y reste physique.
@Model
final class PersonalPin: Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var game: String = Game.reference.rawValue
    /// Peut être vide, et ce n'est pas un oubli : l'épingle existe AVANT d'avoir
    /// un nom, puisqu'on la pose d'un geste et qu'on la nomme dans sa fiche. Le
    /// carnet affiche « Sans nom », jamais une ligne vide.
    var title: String
    var note: String = ""
    var icon: String = PersonalPinIcon.marker.rawValue
    var isDone: Bool = false
    var createdAt: Date
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        game: Game = .reference,
        title: String,
        note: String = "",
        icon: PersonalPinIcon = .marker,
        isDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.game = game.rawValue
        self.title = title
        self.note = note
        self.icon = icon.rawValue
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
    }

    var iconValue: PersonalPinIcon { PersonalPinIcon.from(rawValue: icon) }
    var gameValue: Game { Game(rawValue: game) ?? .reference }
    var position: NormalizedPoint { NormalizedPoint(x: x, y: y) }
}
```

- [ ] **Step 5 : Lancer les tests**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | tail -20
```

Attendu : les trois tests passent. Le reste de la cible ne compile plus encore — c'est normal, `MapModel.addPersonalPin` appelle `PersonalPin(x:y:title:)` qui existe toujours. Si un appelant casse, le corriger ici.

- [ ] **Step 6 : Commit**

```sh
git status   # Localizable.xcstrings ne doit PAS apparaître
git add NeonCompass/Core/Map/PersonalPinIcon.swift NeonCompass/Core/Map/PersonalPin.swift \
        NeonCompassTests/Map/PersonalPinStoreTests.swift NeonCompass.xcodeproj
git commit -m "feat(carte): une épingle porte sa carte, une icône, une note et une coche"
```

---

## Task 2 : Le magasin

**Files:**
- Create: `NeonCompass/Core/Map/PersonalPinStore.swift`
- Test: `NeonCompassTests/Map/PersonalPinStoreTests.swift` (complété)

**Interfaces:**
- Consomme : `PersonalPin`, `PersonalPinIcon`, `Game`, `NormalizedPoint`.
- Produit : `@Observable @MainActor final class PersonalPinStore` avec
  - `init(modelContext: ModelContext)`
  - `private(set) var pins: [PersonalPin]` — toutes cartes confondues, triées par `createdAt`
  - `private(set) var generation: Int`
  - `static let freeCap = 20`
  - `func pins(for game: Game) -> [PersonalPin]`
  - `func isAtCap(isProEntitled: Bool) -> Bool`
  - `@discardableResult func create(at: NormalizedPoint, game: Game, isProEntitled: Bool) -> PersonalPin?`
  - `func update(_ pin: PersonalPin, title: String, note: String)`
  - `func setIcon(_ icon: PersonalPinIcon, on pin: PersonalPin)`
  - `func toggleDone(_ pin: PersonalPin)`
  - `func delete(_ pin: PersonalPin)`
  - `func refresh()`

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `NeonCompassTests/Map/PersonalPinStoreTests.swift`, à l'intérieur de `struct PersonalPinStoreTests` :

```swift
    // MARK: - Plafond

    /// Vingt en gratuit, toutes cartes confondues — un plafond PAR carte en
    /// vaudrait quarante et ne voudrait plus rien dire.
    @Test func theFreeCapBlocksTheTwentyFirstPin() {
        let store = PersonalPinStore(modelContext: makeContext())
        for index in 0..<PersonalPinStore.freeCap {
            let created = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false)
            #expect(created != nil, "la création \(index) aurait dû passer")
        }
        #expect(store.isAtCap(isProEntitled: false))
        #expect(store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false) == nil)
        #expect(store.pins.count == PersonalPinStore.freeCap)
    }

    /// Le plafond compte les DEUX cartes : quinze ici plus dix là doivent buter.
    @Test func theCapCountsEveryMapTogether() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<15 { store.create(at: NormalizedPoint(x: 0.1, y: 0.1), game: .reference, isProEntitled: false) }
        for _ in 0..<5 { store.create(at: NormalizedPoint(x: 0.2, y: 0.2), game: .leonida, isProEntitled: false) }
        #expect(store.create(at: NormalizedPoint(x: 0.3, y: 0.3), game: .leonida, isProEntitled: false) == nil)
    }

    @Test func proHasNoCap() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<(PersonalPinStore.freeCap + 5) {
            store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)
        }
        #expect(store.pins.count == PersonalPinStore.freeCap + 5)
        #expect(store.isAtCap(isProEntitled: true) == false)
    }

    /// Règle de déclassement : on ne supprime JAMAIS. Un carnet au-dessus du
    /// plafond reste entièrement modifiable — seul l'ajout est fermé.
    @Test func anOverCapNotebookStaysEditable() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<25 { store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true) }
        let pin = store.pins[0]
        store.update(pin, title: "Renommée", note: "Toujours modifiable")
        store.toggleDone(pin)
        #expect(pin.title == "Renommée")
        #expect(pin.isDone)
        store.delete(pin)
        #expect(store.pins.count == 24)
    }

    // MARK: - Portée par carte

    /// Le bug que ce chantier répare : une épingle ne doit apparaître que sur la
    /// carte où elle a été posée.
    @Test func aPinBelongsToExactlyOneMap() {
        let store = PersonalPinStore(modelContext: makeContext())
        store.create(at: NormalizedPoint(x: 0.1, y: 0.1), game: .reference, isProEntitled: true)
        store.create(at: NormalizedPoint(x: 0.2, y: 0.2), game: .leonida, isProEntitled: true)
        #expect(store.pins(for: .reference).count == 1)
        #expect(store.pins(for: .leonida).count == 1)
        #expect(store.pins(for: .reference)[0].gameValue == .reference)
    }

    // MARK: - Générations

    /// Sans génération qui avance, le moteur de carte ne repousse pas son
    /// contenu et l'épingle posée n'apparaît jamais.
    @Test func creatingDeletingAndTogglingAdvanceTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        var seen: Set<Int> = [store.generation]
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        #expect(seen.insert(store.generation).inserted, "la création n'a pas avancé la génération")
        store.toggleDone(pin)
        #expect(seen.insert(store.generation).inserted, "la coche n'a pas avancé la génération")
        store.setIcon(.vehicle, on: pin)
        #expect(seen.insert(store.generation).inserted, "l'icône n'a pas avancé la génération")
        store.delete(pin)
        #expect(seen.insert(store.generation).inserted, "la suppression n'a pas avancé la génération")
    }

    /// Le titre et la note ne changent PAS le dessin de l'épingle : les commettre
    /// ne doit pas périmer le contenu du moteur, sans quoi chaque session
    /// d'édition ferait rebâtir toutes les pastilles de la carte.
    @Test func editingTextDoesNotAdvanceTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        let before = store.generation
        store.update(pin, title: "Un nom", note: "Une note")
        #expect(store.generation == before)
    }

    // MARK: - updatedAt

    @Test func editingMovesUpdatedAtOnlyWhenSomethingChanged() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = .distantPast
        store.update(pin, title: "", note: "")   // rien n'a changé : le titre était déjà vide
        #expect(pin.updatedAt == .distantPast, "une édition sans changement ne doit pas dater l'épingle")
        store.update(pin, title: "Un nom", note: "")
        #expect(pin.updatedAt > .distantPast)
    }

    /// Le magasin relit le disque, comme `FoundStore.refresh` : les tests et les
    /// chemins d'amorçage insèrent parfois par-derrière.
    @Test func refreshSeesWritesMadeBehindTheStore() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        context.insert(PersonalPin(x: 0.4, y: 0.4, game: .reference, title: "Par-derrière"))
        try? context.save()
        #expect(store.pins.isEmpty)
        store.refresh()
        #expect(store.pins.count == 1)
    }
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | tail -20
```

Attendu : ÉCHEC de compilation — `cannot find 'PersonalPinStore' in scope`.

- [ ] **Step 3 : Écrire le magasin**

Créer `NeonCompass/Core/Map/PersonalPinStore.swift` :

```swift
import Foundation
import Observation
import SwiftData

/// Le carnet de chasse — propriétaire unique des épingles personnelles.
///
/// **Pourquoi il existe.** Les épingles vivaient dans `MapModel`, qui porte déjà
/// le filtrage des POI, l'état trouvé et la synchro de progression : c'est le
/// fichier qui grossit à chaque chantier. Elles sont désormais lues par trois
/// vues — la carte, la fiche, le carnet — dont deux n'ont besoin de rien
/// d'autre. Et le chantier 2 branchera la synchro ici, comme `FoundStore` porte
/// la sienne.
///
/// **Le plafond vit ici, pas dans la vue**, et le droit Pro lui est passé en
/// paramètre : le magasin ne connaît pas `ProEntitlementModel`, ce qui le laisse
/// testable sans StoreKit. `create` renvoie `nil` quand le plafond mord — un
/// `Optional` plutôt qu'un lancer, parce que buter sur le plafond n'est pas une
/// anomalie mais une réponse.
///
/// `@MainActor` : un `ModelContext` de la fenêtre principale, lu par des corps de
/// vues.
@Observable
@MainActor
final class PersonalPinStore {
    /// Toutes cartes confondues, triées par date de création. Le découpage par
    /// carte se fait à la lecture (`pins(for:)`) : la liste entière sert au
    /// décompte du plafond, qui ignore les cartes.
    private(set) var pins: [PersonalPin] = []

    /// Donne au moteur de carte un moyen en O(1) de savoir si le calque a changé.
    /// `PersonalPin` est une classe : comparer les tableaux ne dirait rien d'une
    /// coche basculée, et compter les éléments encore moins.
    private(set) var generation = 0

    /// Vingt en gratuit, TOUTES CARTES CONFONDUES — un plafond par carte en
    /// vaudrait quarante et ne voudrait plus rien dire.
    static let freeCap = 20

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    func refresh() {
        let descriptor = FetchDescriptor<PersonalPin>(sortBy: [SortDescriptor(\.createdAt)])
        pins = (try? modelContext.fetch(descriptor)) ?? []
        generation &+= 1
    }

    func pins(for game: Game) -> [PersonalPin] {
        pins.filter { $0.gameValue == game }
    }

    func isAtCap(isProEntitled: Bool) -> Bool {
        !isProEntitled && pins.count >= Self.freeCap
    }

    /// Pose une épingle sans nom : elle existe d'abord, elle se nomme ensuite
    /// dans sa fiche. C'est ce qui permet d'en poser cinq en dix secondes manette
    /// en main — et ce qui fait qu'un titre vide n'est plus un piège silencieux.
    ///
    /// - Returns: `nil` quand le plafond gratuit est atteint. L'appelant en fait
    ///   un mur, ce n'est pas au magasin de le dessiner.
    @discardableResult
    func create(at point: NormalizedPoint, game: Game, isProEntitled: Bool) -> PersonalPin? {
        guard !isAtCap(isProEntitled: isProEntitled) else { return nil }
        let pin = PersonalPin(x: point.x, y: point.y, game: game, title: "")
        modelContext.insert(pin)
        save()
        refresh()
        return pin
    }

    /// Commit d'une SESSION d'édition, jamais d'une frappe.
    ///
    /// La fiche garde le titre et la note dans un `@State` local et n'appelle
    /// ceci qu'à la perte de focus, à la validation ou à la fermeture du panneau.
    /// Le piège est mesuré et documenté dans `MapModel` : taper un caractère dans
    /// le champ de nom coûtait une requête SwiftData plus un filtrage des 537
    /// points.
    ///
    /// **N'avance pas la génération**, et c'est délibéré : ni le titre ni la note
    /// ne changent le dessin de l'épingle. Les périmer ferait rebâtir toutes les
    /// pastilles visibles pour un texte que la carte n'affiche pas. Conséquence
    /// acceptée : l'étiquette d'accessibilité de l'épingle porte l'ancien titre
    /// jusqu'au prochain changement de calque.
    func update(_ pin: PersonalPin, title: String, note: String) {
        guard pin.title != title || pin.note != note else { return }
        pin.title = title
        pin.note = note
        pin.updatedAt = .now
        save()
    }

    func setIcon(_ icon: PersonalPinIcon, on pin: PersonalPin) {
        guard pin.icon != icon.rawValue else { return }
        pin.icon = icon.rawValue
        pin.updatedAt = .now
        save()
        bumpGeneration()
    }

    func toggleDone(_ pin: PersonalPin) {
        pin.isDone.toggle()
        pin.updatedAt = .now
        save()
        bumpGeneration()
    }

    /// Suppression PHYSIQUE. Le chantier 2 la bascule en pierre tombale
    /// (`deletedAt`) parce qu'un `delete` local ne se propage pas : sans elle,
    /// une épingle effacée sur l'iPhone reviendrait depuis l'iPad.
    func delete(_ pin: PersonalPin) {
        modelContext.delete(pin)
        save()
        refresh()
    }

    private func bumpGeneration() {
        generation &+= 1
    }

    private func save() {
        try? modelContext.save()
    }
}
```

- [ ] **Step 4 : Lancer les tests**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | tail -30
```

Attendu : les douze tests passent.

- [ ] **Step 5 : Commit**

```sh
git status
git add NeonCompass/Core/Map/PersonalPinStore.swift NeonCompassTests/Map/PersonalPinStoreTests.swift NeonCompass.xcodeproj
git commit -m "feat(carte): un magasin possède le carnet, et porte son plafond"
```

---

## Task 3 : Le déménagement — `MapModel` cède les épingles, la sélection devient une somme

**Files:**
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Features/Map/PersonalPinListSheet.swift` (adapté, supprimé en tâche 7)
- Modify: `NeonCompassTests/Map/MapContentTokenTests.swift`

**Interfaces:**
- Consomme : `PersonalPinStore` (tâche 2).
- Produit :
  - `enum MapSelection: Equatable { case poi(POI), pin(PersonalPin) }` avec `var poi: POI?` et `var pin: PersonalPin?`.
  - `MapModel.selection: MapSelection?` remplace `MapModel.selectedPOI`.
  - `MapModel` perd `personalPins`, `personalPinsGeneration`, `addPersonalPin`, `deletePersonalPin`.
  - `NeonCompassApp` injecte `PersonalPinStore` par `.environment`.

- [ ] **Step 1 : Écrire le test qui échoue**

Dans `NeonCompassTests/Map/PersonalPinStoreTests.swift`, ajouter :

```swift
    // MARK: - Sélection

    /// Le panneau tient une référence à l'épingle sélectionnée. La supprimer sans
    /// vider la sélection laisserait le panneau sur un objet effacé.
    @Test func deletingTheSelectedPinClearsTheSelection() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let model = MapModel(pois: [], modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        model.selection = .pin(pin)
        #expect(model.selection?.pin === pin)
        model.clearSelectionIfPin(pin)
        #expect(model.selection == nil)
    }

    /// La somme interdit l'état impossible : deux natures ne peuvent pas être
    /// sélectionnées en même temps, ce que deux `Optional` côte à côte auraient
    /// laissé exprimer.
    @Test func selectingAPOIReplacesASelectedPin() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let model = MapModel(pois: [], modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        model.selection = .pin(pin)
        let poi = POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                      title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
        model.selection = .poi(poi)
        #expect(model.selection?.pin == nil)
        #expect(model.selection?.poi?.id == "a")
    }
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | tail -20
```

Attendu : ÉCHEC — `value of type 'MapModel' has no member 'selection'`.

- [ ] **Step 3 : Modifier `MapModel`**

Dans `NeonCompass/Features/Map/MapModel.swift` :

Remplacer la ligne `var selectedPOI: POI?` par :

```swift
    /// Ce que le panneau montre. Une SOMME, et non deux `Optional` côte à côte :
    /// le panneau accueille désormais deux natures et ne peut en montrer qu'une,
    /// or deux facultatifs laisseraient exprimer l'état impossible où les deux
    /// sont non nuls, qu'aucun type n'interdirait.
    var selection: MapSelection?
```

Supprimer les quatre membres suivants (les épingles appartiennent au magasin) :
`private(set) var personalPins`, `private(set) var personalPinsGeneration`, `refreshPersonalPins()`, `addPersonalPin(at:title:)`, `deletePersonalPin(_:)`, ainsi que l'appel `refreshPersonalPins()` dans `init`.

Ajouter en fin de classe :

```swift
    /// Vide la sélection si elle porte cette épingle. Appelé AVANT la
    /// suppression : le panneau tient une référence, et un objet SwiftData
    /// effacé sous elle est un plantage en attente.
    func clearSelectionIfPin(_ pin: PersonalPin) {
        if selection?.pin === pin { selection = nil }
    }
```

Ajouter en fin de fichier, hors de la classe :

```swift
/// Ce qu'on peut sélectionner sur la carte.
///
/// `POI` est une valeur, `PersonalPin` une classe SwiftData — `@Model` est déjà
/// `Hashable`, donc l'égalité synthétisée compare l'identité pour l'épingle et le
/// contenu pour le point. C'est exactement ce qu'il faut : rouvrir la même
/// épingle après l'avoir renommée ne doit pas rejouer la transition du panneau.
enum MapSelection: Equatable {
    case poi(POI)
    case pin(PersonalPin)

    var poi: POI? { if case .poi(let poi) = self { return poi } else { return nil } }
    var pin: PersonalPin? { if case .pin(let pin) = self { return pin } else { return nil } }
}
```

- [ ] **Step 4 : Injecter le magasin dans l'app**

Dans `NeonCompass/App/NeonCompassApp.swift`, après `@State private var foundStore: FoundStore` ajouter :

```swift
    /// Construit ici et non dans l'écran : un magasin bâti par `MapScreen` serait
    /// reconstruit à chaque bascule d'onglet sur iPad, et le carnet ouvert depuis
    /// un autre écran verrait une autre liste. Même raison que `FoundStore`.
    @State private var personalPinStore: PersonalPinStore
```

Dans `init()`, après `_foundStore = State(...)` :

```swift
        _personalPinStore = State(initialValue: PersonalPinStore(modelContext: container.mainContext))
```

Dans `body`, après `.environment(foundStore)` :

```swift
                .environment(personalPinStore)
```

- [ ] **Step 5 : Rebrancher les appelants**

Dans `NeonCompass/Features/Map/MapScreen.swift` :

- ajouter `@Environment(PersonalPinStore.self) private var personalPinStore` auprès des autres `@Environment` ;
- remplacer `personalPins: model.personalPins` par `personalPins: personalPinStore.pins(for: mapGame)` ;
- remplacer `personalPinsGeneration: model.personalPinsGeneration` par `personalPinsGeneration: personalPinStore.generation` ;
- remplacer chaque `model.selectedPOI` par `model.selection` en adaptant :
  - `if let selected = model.selectedPOI` → `if let poi = model.selection?.poi` (la branche épingle arrive en tâche 6),
  - `onTapPOI: { poi in model.selectedPOI = poi }` → `onTapPOI: { poi in model.selection = .poi(poi) }`,
  - `model.selectedPOI = nil` → `model.selection = nil`,
  - `.animation(.snappy, value: model.selectedPOI)` → `.animation(.snappy, value: model.selection)` ;
- remplacer le corps du bouton de l'alerte par un appel au magasin, provisoirement (l'alerte disparaît en tâche 6) :

```swift
            Button("map.personalPins.save") {
                if let location = pendingPinLocation, !pendingPinTitle.isEmpty {
                    if let pin = personalPinStore.create(at: location, game: mapGame, isProEntitled: proEntitlementModel.isProEntitled) {
                        personalPinStore.update(pin, title: pendingPinTitle, note: "")
                    }
                }
                pendingPinTitle = ""
                pendingPinLocation = nil
                showPersonalPinAlert = false
            }
```

Dans `NeonCompass/Features/Map/PersonalPinListSheet.swift`, remplacer intégralement (il disparaît en tâche 7) :

```swift
import SwiftUI

struct PersonalPinListSheet: View {
    let store: PersonalPinStore
    let game: Game

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.pins(for: game)) { pin in
                    Text(pin.title)
                }
                .onDelete { offsets in
                    let pins = store.pins(for: game)
                    for index in offsets { store.delete(pins[index]) }
                }
            }
            .navigationTitle(Text("map.personalPins.title"))
        }
    }
}
```

et son site d'appel dans `MapScreen` : `PersonalPinListSheet(store: personalPinStore, game: mapGame)`.

- [ ] **Step 6 : Rebrancher `MapContentTokenTests`**

Dans `NeonCompassTests/Map/MapContentTokenTests.swift`, remplacer les trois tests de la section « Épingles personnelles » par :

```swift
    // MARK: - Épingles personnelles

    /// Le cas qui a motivé ce compteur : sans lui, poser une épingle ne
    /// changerait rien de comparable et la carte ne la dessinerait jamais.
    @Test func addingAPersonalPinAdvancesItsGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let before = store.generation
        store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)
        #expect(store.generation != before)
        #expect(store.pins.count == 1)
    }

    /// Supprimer compte autant qu'ajouter : une épingle retirée doit disparaître.
    @Test func deletingAPersonalPinAdvancesItsGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        let before = store.generation
        store.delete(pin)
        #expect(store.generation != before)
        #expect(store.pins.isEmpty)
    }

    /// Deux épingles successives doivent donner deux générations distinctes —
    /// un compteur qui se contenterait de basculer entre deux valeurs
    /// retomberait sur la précédente une fois sur deux.
    @Test func successivePersonalPinsNeverRepeatAGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        var seen: Set<Int> = [store.generation]
        for index in 0..<5 {
            store.create(at: NormalizedPoint(x: 0.1 * Double(index), y: 0.5), game: .reference, isProEntitled: true)
            #expect(seen.insert(store.generation).inserted, "génération déjà vue au tour \(index)")
        }
    }
```

- [ ] **Step 7 : Compiler et lancer toute la suite carte**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```

Attendu : compilation propre, suite verte. Corriger tout appelant résiduel de `selectedPOI` que le compilateur signale.

- [ ] **Step 8 : Commit**

```sh
git status   # restaurer Localizable.xcstrings s'il a bougé
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
git add -A
git commit -m "refactor(carte): le carnet quitte MapModel, la sélection devient une somme"
```

---

## Task 4 : L'épingle s'éteint quand elle est faite, et se laisse taper

**Files:**
- Modify: `NeonCompass/Core/Map/MapPinViews.swift`
- Modify: `NeonCompass/Core/Map/MapScrollView.swift`
- Test: `NeonCompassTests/Map/MapPinShapeTests.swift`

**Interfaces:**
- Consomme : `PersonalPin.isDone`, `PersonalPin.iconValue`, `POIPinPalette.coreOpacity(found:)`, `ringWidth(found:)`, `glowRadius(for:found:)`, `MapPinMetrics.hitSides(for:cap:)`.
- Produit :
  - `DroppedPinView` gagne `let isDone: Bool` (les appelants communautaires passent `false`).
  - `MapContentSwiftUIView` gagne `let onTapPersonalPin: (PersonalPin) -> Void` et `let showPersonalPins: Bool`.
  - `TiledMapRepresentable` gagne `let onTapPersonalPin: (PersonalPin) -> Void` et `var showPersonalPins: Bool = true`.

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans `NeonCompassTests/Map/MapPinShapeTests.swift` :

```swift
    /// Les zones de frappe des épingles personnelles doivent entrer dans le MÊME
    /// balayage que les groupes éditoriaux.
    ///
    /// Le commentaire d'origine de `editorialHitSides` justifiait de les exclure
    /// par le fait qu'elles « ne se tapent pas du tout ». Ce n'est plus vrai : une
    /// épingle posée à côté d'un lieu lui volerait ses taps avec ses 44 pt.
    /// L'argument de non-recouvrement est géométrique, il ne connaît pas les
    /// familles.
    @Test func aPersonalPinDoesNotStealItsNeighboursTaps() {
        // Deux points distants de 30 pt de contenu, avec un plafond de 44 :
        // aucun des deux ne doit garder le plafond.
        let positions = [CGPoint(x: 100, y: 100), CGPoint(x: 130, y: 100)]
        let sides = MapPinMetrics.hitSides(for: positions, cap: 44)
        #expect(sides.count == 2)
        for side in sides {
            #expect(side <= 30.5, "zone de \(side) pt pour des voisins à 30 pt : elles se recouvrent")
        }
    }

    /// Et la réciproque : isolées, elles gardent leur pleine cible.
    @Test func anIsolatedPinKeepsTheFullTarget() {
        let positions = [CGPoint(x: 100, y: 100), CGPoint(x: 600, y: 600)]
        let sides = MapPinMetrics.hitSides(for: positions, cap: 44)
        #expect(sides.allSatisfy { abs($0 - 44) < 0.001 })
    }
```

- [ ] **Step 2 : Lancer pour vérifier**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapPinShapeTests 2>&1 | tail -20
```

Attendu : PASSE déjà — `hitSides` est correcte, c'est son *usage* qui exclut les épingles. Ces deux tests verrouillent le contrat sur lequel repose la suite ; s'ils échouaient, la tâche s'arrêterait ici.

- [ ] **Step 3 : `DroppedPinView` gagne son état**

Dans `NeonCompass/Core/Map/MapPinViews.swift`, remplacer la déclaration et le corps de `DroppedPinView` :

```swift
struct DroppedPinView: View, Equatable {
    let symbol: String
    let tint: Color
    let style: MapStyle
    /// Une épingle faite s'éteint EXACTEMENT comme un lieu trouvé et comme un
    /// groupe complété — mêmes fonctions de palette, donc même sémantique. Le
    /// joueur n'a pas un second langage visuel à apprendre, et le halo qui
    /// s'éteint tient la consigne du CLAUDE.md (« glow on at most three accents
    /// per screen ») à mesure que le carnet se remplit.
    var isDone: Bool = false
    let accessibilityTitle: String

    static let headWidth: CGFloat = 22
    static var height: CGFloat { headWidth * 1.36 }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint.opacity(isDone ? 0.6 : 1))
            .frame(width: Self.headWidth, height: Self.headWidth)
            .frame(width: Self.headWidth, height: Self.height, alignment: .top)
            .background(MapPinTeardrop().fill(POIPinPalette.core(for: style).opacity(POIPinPalette.coreOpacity(found: isDone))))
            .overlay(MapPinTeardrop().stroke(tint.opacity(isDone ? 0.6 : 1), lineWidth: POIPinPalette.ringWidth(found: isDone)))
            .shadow(color: tint.opacity(0.5), radius: POIPinPalette.glowRadius(for: style, found: isDone))
            // La POINTE désigne le lieu, pas le centre de la forme. `position`
            // pose les centres : sans ce décalage, chaque épingle indiquerait un
            // point situé une demi-hauteur trop bas. Il est posé DEDANS pour
            // être mis à l'échelle avec le reste par la contre-échelle du zoom.
            .offset(y: -Self.height / 2)
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityValue(isDone ? Text("map.pins.card.done") : Text(verbatim: ""))
    }
}
```

- [ ] **Step 4 : Rendre l'épingle tapable et joindre les deux familles**

Dans `NeonCompass/Core/Map/MapScrollView.swift` :

Sur `MapContentSwiftUIView`, ajouter auprès des autres fermetures :

```swift
    let onTapPersonalPin: (PersonalPin) -> Void
    var showPersonalPins: Bool = true
```

Remplacer `editorialHitSides` par un balayage unique, et adapter `body` :

```swift
    /// Côtés des zones de frappe, indexés par identifiant, pour TOUT ce qui se
    /// tape et s'ouvre en fiche : groupes éditoriaux et épingles personnelles.
    ///
    /// Les deux familles passent dans le MÊME balayage depuis que l'épingle est
    /// tapable. Le commentaire précédent justifiait de l'exclure par le fait
    /// qu'elle « ne se tape pas du tout » — une épingle posée à côté d'un lieu
    /// lui volerait désormais ses taps avec ses 44 pt. L'argument de
    /// non-recouvrement est géométrique, il ne connaît pas les familles.
    ///
    /// Les propositions communautaires restent dehors, comme avant : elles sont
    /// rares — il n'y en a aucune sur la carte de référence — et portent leur
    /// propre surface interactive.
    private var tappableHitSides: [String: CGFloat] {
        let visibleClusters = clusters
        let visiblePins = visiblePersonalPins
        let points = visibleClusters.map { MapGeometry.contentPoint(for: $0.position, manifest: manifest) }
            + visiblePins.map { MapGeometry.contentPoint(for: $0.position, manifest: manifest) }
        let sides = MapPinMetrics.hitSides(for: points, cap: zoom.pinHitCap)
        let ids = visibleClusters.map(\.id) + visiblePins.map { "p\($0.id.uuidString)" }
        return Dictionary(uniqueKeysWithValues: zip(ids, sides))
    }
```

Dans `body`, remplacer `let hitSides = editorialHitSides` par `let hitSides = tappableHitSides`, et le bloc des épingles par :

```swift
            if showPersonalPins {
                ForEach(visiblePersonalPins) { pin in
                    personalPin(pin, hitSide: hitSides["p\(pin.id.uuidString)"] ?? zoom.pinHitCap)
                }
            }
```

Remplacer `visiblePersonalPins` et `personalPin(_:)` :

```swift
    /// Épingles personnelles et brouillons passent par la même fenêtre : ils
    /// sont peu nombreux aujourd'hui, mais rien ne garantit qu'ils le restent,
    /// et une exception silencieuse serait une régression en attente.
    ///
    /// Le filtrage par CARTE, lui, se fait en amont (`PersonalPinStore.pins(for:)`)
    /// et non ici : le moteur ne reçoit que les épingles de la carte affichée.
    private var visiblePersonalPins: [PersonalPin] {
        personalPins.filter { zoom.window.contains($0.position) }
    }

    /// Le `Button` est ICI et non dans `DroppedPinView` : la vue comparée doit
    /// rester pure valeur (cf. l'en-tête de `MapPinViews`) — une fermeture n'est
    /// ni comparable ni `Sendable`, et sa seule présence ferait échouer la
    /// conformité à `Equatable` sous concurrence stricte.
    private func personalPin(_ pin: PersonalPin, hitSide: CGFloat) -> some View {
        Button {
            onTapPersonalPin(pin)
        } label: {
            DroppedPinView(
                symbol: pin.iconValue.symbol,
                tint: NCColor.sunsetOrange,
                style: style,
                isDone: pin.isDone,
                accessibilityTitle: pin.title.isEmpty ? String(localized: "map.pins.untitled") : pin.title
            )
            .equatable()
            .pinHitArea(side: hitSide)
        }
        .buttonStyle(.plain)
        .scaleEffect(pinScale)
        .position(MapGeometry.contentPoint(for: pin.position, manifest: manifest))
    }
```

Sur `TiledMapRepresentable`, ajouter auprès des autres fermetures :

```swift
    let onTapPersonalPin: (PersonalPin) -> Void
    var showPersonalPins: Bool = true
```

Dans `ContentToken`, ajouter le drapeau — sans lui, éteindre le calque ne prendrait effet qu'au prochain changement de données :

```swift
        let showPersonalPins: Bool
```

et dans `contentToken`, `showPersonalPins: showPersonalPins,`.

Dans `makeContent(zoom:coordinator:)`, passer les deux :

```swift
            onTapPersonalPin: onTapPersonalPin,
            showPersonalPins: showPersonalPins,
```

Dans `ContributionAnnotationView`, l'appel à `DroppedPinView` reste inchangé : `isDone` a une valeur par défaut.

- [ ] **Step 5 : Brancher provisoirement l'appelant**

Dans `NeonCompass/Features/Map/MapScreen.swift`, ajouter dans l'appel à `TiledMapRepresentable`, après `onTapPOI:` :

```swift
                onTapPersonalPin: { pin in model.selection = .pin(pin) },
```

- [ ] **Step 6 : Compiler et tester**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapPinShapeTests 2>&1 | tail -20
```

Attendu : compilation propre, tests verts. La clé `map.pins.untitled` n'existe pas encore — elle est ajoutée en tâche 8 et `String(localized:)` renvoie la clé nue en attendant, ce qui ne casse pas la compilation.

- [ ] **Step 7 : Commit**

```sh
git status
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
git add -A
git commit -m "feat(carte): l'épingle s'éteint quand elle est faite, et se laisse taper"
```

---

## Task 5 : Viser un point sur la carte

**Files:**
- Modify: `NeonCompass/Core/Map/MapScrollView.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`

**Interfaces:**
- Produit :
  - `struct MapFocusRequest: Equatable { let id: UUID; let position: NormalizedPoint }` — dans `MapScrollView.swift`, sous `TiledMapRepresentable`.
  - `TiledMapRepresentable` gagne `@Binding var focusRequest: MapFocusRequest?`.
  - `Coordinator.focus(on:manifest:)`.
  - `Coordinator.consumedFocus: UUID?`.

- [ ] **Step 1 : Ajouter le type de requête**

Dans `NeonCompass/Core/Map/MapScrollView.swift`, avant `struct TiledMapRepresentable` :

```swift
/// Demande de recentrage sur un point, émise par le carnet et consommée une
/// seule fois par le moteur.
///
/// L'identifiant est ce qui rend la requête consommable : viser DEUX FOIS la
/// même épingle doit recentrer deux fois, or deux requêtes de même position
/// seraient égales et la seconde passerait pour déjà traitée.
struct MapFocusRequest: Equatable {
    let id: UUID
    let position: NormalizedPoint

    init(position: NormalizedPoint) {
        self.id = UUID()
        self.position = position
    }
}
```

- [ ] **Step 2 : Ajouter la liaison et la consommation**

Sur `TiledMapRepresentable`, auprès de `@Binding var viewport` :

```swift
    @Binding var focusRequest: MapFocusRequest?
```

Dans `updateUIView`, **tout en haut du corps, avant le test sur `displayedGame`** :

```swift
        // Lu AVANT le garde-fou du jeton, et c'est tout le sujet : ce garde-fou
        // retourne dès que rien de la carte n'a changé, ce qui est précisément le
        // cas quand on ne fait que viser une épingle déjà dessinée. Placé après,
        // il l'avalerait.
        if let focusRequest, context.coordinator.consumedFocus != focusRequest.id {
            context.coordinator.consumedFocus = focusRequest.id
            context.coordinator.focus(on: focusRequest.position, manifest: manifest)
        }
```

Dans `Coordinator`, auprès de `displayedGame` :

```swift
        /// Dernière requête de recentrage honorée. Sans elle, chaque
        /// `updateUIView` — et il y en a beaucoup — rejouerait la même visée.
        fileprivate var consumedFocus: UUID?
```

et après `zoom(to:manifest:)` :

```swift
        /// Recentre sur un point, à une échelle qui ne DÉZOOME jamais.
        ///
        /// Distinct de `zoom(to:)`, qui double le zoom pour délier un groupe :
        /// ici la position est connue et c'est le cadrage qui compte. L'échelle
        /// visée est la plus grande entre le zoom courant et deux fois le
        /// minimum — sans ce plancher, viser depuis le carnet laisserait
        /// l'épingle en point de deux pixels au dézoom de repos ; sans le
        /// maximum, taper une ligne ferait RECULER un joueur qui venait de
        /// zoomer sur son quartier.
        func focus(on position: NormalizedPoint, manifest: MapManifest) {
            guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let target = min(max(scrollView.zoomScale, scrollView.minimumZoomScale * 2), scrollView.maximumZoomScale)
            let center = MapGeometry.contentPoint(for: position, manifest: manifest)
            let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
            scrollView.zoom(
                to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height),
                animated: true
            )
        }
```

- [ ] **Step 3 : Brancher l'écran**

Dans `NeonCompass/Features/Map/MapScreen.swift`, auprès de `@State private var viewport` :

```swift
    @State private var focusRequest: MapFocusRequest?
```

et dans l'appel à `TiledMapRepresentable`, après `viewport: $viewport,` :

```swift
                focusRequest: $focusRequest,
```

- [ ] **Step 4 : Compiler**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Attendu : compilation propre.

- [ ] **Step 5 : Commit**

```sh
git status
git add -A
git commit -m "feat(carte): le moteur sait viser un point sans dézoomer"
```

---

## Task 6 : La fiche

**Files:**
- Create: `NeonCompass/Features/Map/PersonalPinCardView.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`

**Interfaces:**
- Consomme : `PersonalPinStore`, `PersonalPin`, `PersonalPinIcon`, `MapSelection`.
- Produit : `struct PersonalPinCardView: View` — `init(pin:store:onDismiss:)`.

- [ ] **Step 1 : Écrire la fiche**

Créer `NeonCompass/Features/Map/PersonalPinCardView.swift` :

```swift
import SwiftUI

/// La fiche d'une épingle — l'UNIQUE surface du carnet : créer, nommer,
/// annoter, illustrer, cocher, supprimer.
///
/// Elle est unique par choix : l'épingle est posée d'un geste puis nommée ici,
/// ce qui évite une feuille de création qui dirait exactement les mêmes choses.
/// Le titre est donc TOUJOURS éditable — il n'y a pas de mode édition à armer.
///
/// Elle porte la même coquille de verre que `POIDetailView`, et la même croix de
/// 44 pt : sur iPad, le panneau latéral n'a pas d'autre sortie.
struct PersonalPinCardView: View {
    let pin: PersonalPin
    let store: PersonalPinStore
    let onDismiss: () -> Void
    let onDelete: () -> Void

    /// Le titre et la note vivent en LOCAL et ne sont commis qu'à la perte de
    /// focus, à la validation ou à la disparition de la fiche — jamais à la
    /// frappe.
    ///
    /// Le piège est mesuré, et son commentaire est encore dans `MapModel` : taper
    /// un caractère dans le champ de nom d'une épingle coûtait une requête
    /// SwiftData PLUS un filtrage des 537 points, parce que chaque frappe
    /// réévaluait le corps de l'écran. Une écriture par session d'édition, c'est
    /// aussi ce qu'il faut au chantier 2 — `updatedAt` avance une fois, pas
    /// trente.
    @State private var draftTitle: String
    @State private var draftNote: String
    @FocusState private var focusedField: Field?
    @State private var showDeleteConfirmation = false

    private enum Field: Hashable { case title, note }

    init(pin: PersonalPin, store: PersonalPinStore, onDismiss: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.pin = pin
        self.store = store
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _draftTitle = State(initialValue: pin.title)
        _draftNote = State(initialValue: pin.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("map.pins.card.titlePlaceholder", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit(commit)
                Spacer(minLength: 0)
                Button {
                    commit()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -10)
                .accessibilityLabel(Text("poi.detail.close"))
            }

            iconRow

            TextField("map.pins.card.notePlaceholder", text: $draftNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(NCTypography.body)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .focused($focusedField, equals: .note)

            Button {
                commit()
                store.toggleDone(pin)
            } label: {
                Group {
                    if pin.isDone {
                        Label("map.pins.card.done", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("map.pins.card.markDone", systemImage: "circle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            // Les teintes exactes de « marquer trouvé » sur un POI : le carnet
            // n'invente pas un second vocabulaire pour dire la même chose.
            .tint(pin.isDone ? NCColor.neonCyan : NCColor.sunsetMagenta)

            Button("map.pins.card.delete", systemImage: "trash", role: .destructive) {
                showDeleteConfirmation = true
            }
            .font(.caption)
            .confirmationDialog(
                "map.pins.card.deleteConfirm",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("map.pins.card.delete", role: .destructive) { onDelete() }
                Button("map.pins.card.cancel", role: .cancel) {}
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
        // La fiche vit dans l'arbre de vues, pas dans une feuille : elle
        // DISPARAÎT quand la sélection change, et c'est le dernier moment où l'on
        // peut sauver ce qui est en cours de frappe.
        .onDisappear(perform: commit)
        .onChange(of: focusedField) { previous, _ in
            if previous != nil { commit() }
        }
        .task {
            // Une épingle sans nom vient d'être posée : le champ prend le focus,
            // et le joueur n'a qu'à taper. Une épingle déjà nommée qu'on rouvre ne
            // fait pas surgir le clavier.
            if pin.title.isEmpty { focusedField = .title }
        }
    }

    private var iconRow: some View {
        HStack(spacing: 8) {
            ForEach(PersonalPinIcon.allCases, id: \.self) { icon in
                Button {
                    store.setIcon(icon, on: pin)
                } label: {
                    Image(systemName: icon.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(icon == pin.iconValue ? NCColor.sunsetOrange : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .overlay(
                            Circle()
                                .strokeBorder(NCColor.sunsetOrange, lineWidth: 2)
                                .opacity(icon == pin.iconValue ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: icon.labelKey)))
                .accessibilityAddTraits(icon == pin.iconValue ? [.isSelected] : [])
            }
        }
    }

    private func commit() {
        store.update(pin, title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), note: draftNote)
    }
}
```

- [ ] **Step 2 : Brancher le panneau à deux natures**

Dans `NeonCompass/Features/Map/MapScreen.swift`, remplacer les deux branches `if let selected = model.selectedPOI { detailPanel(...) }` (compact et régulier) par, respectivement :

```swift
                if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .bottom)
                        .padding(.bottom, 76)
                }
```

```swift
                if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .trailing, width: 340)
                }
```

Remplacer la signature et le corps de `detailPanel` :

```swift
    private func detailPanel(_ selection: MapSelection, model: MapModel, edge: Edge, width: CGFloat? = nil) -> some View {
        Group {
            switch selection {
            case .poi(let poi): poiDetail(poi, model: model)
            case .pin(let pin):
                PersonalPinCardView(
                    pin: pin,
                    store: personalPinStore,
                    onDismiss: { model.selection = nil },
                    onDelete: {
                        // Vider la sélection AVANT la suppression : le panneau
                        // tient une référence, et un objet SwiftData effacé sous
                        // elle est un plantage en attente.
                        model.clearSelectionIfPin(pin)
                        personalPinStore.delete(pin)
                    }
                )
            }
        }
        .frame(width: width)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { drag in
                    let travelled = edge == .bottom ? drag.translation.height : drag.translation.width
                    guard travelled > 60 else { return }
                    model.selection = nil
                }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { model.selection = nil }
        .containerRelativeFrame(.vertical, alignment: edge == .bottom ? .bottom : .center) { height, _ in
            height * 0.55
        }
        .transition(.move(edge: edge))
    }
```

(Le commentaire d'origine de `detailPanel`, qui explique le cadre transparent, le congédiement au balayage et `.isModal`, reste au-dessus de la fonction — il vaut pour les deux natures.)

- [ ] **Step 3 : Remplacer l'alerte de création par la pose directe**

Dans `MapScreen`, supprimer l'état `pendingPinTitle`, `showPersonalPinAlert`, et le bloc `.alert("map.personalPins.addPrompt", ...)` en entier.

Dans le `confirmationDialog` de l'appui long, remplacer le premier bouton :

```swift
            Button("map.longPress.addPersonalPin") {
                guard let location = pendingPinLocation else { return }
                pendingPinLocation = nil
                // L'épingle existe TOUT DE SUITE, et sa fiche s'ouvre dessus,
                // champ de titre prêt à recevoir la frappe. On peut en poser cinq
                // en dix secondes manette en main, ou nommer soigneusement — au
                // choix, et sans deuxième surface à traverser.
                if let pin = personalPinStore.create(
                    at: location,
                    game: mapGame,
                    isProEntitled: proEntitlementModel.isProEntitled
                ) {
                    model.selection = .pin(pin)
                } else {
                    showNotebookFull = true
                }
            }
```

Ajouter l'état correspondant auprès des autres `@State` :

```swift
    @State private var showNotebookFull = false
    @State private var showPaywall = false
```

- [ ] **Step 4 : Compiler et essayer à la main**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Attendu : compilation propre. `showNotebookFull` est encore inutilisé — le mur est dessiné en tâche 8.

- [ ] **Step 5 : Commit**

```sh
git status
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
git add -A
git commit -m "feat(carte): la fiche d'épingle, seule surface pour créer et éditer"
```

---

## Task 7 : Le carnet

**Files:**
- Create: `NeonCompass/Features/Map/PersonalPinBookView.swift`
- Delete: `NeonCompass/Features/Map/PersonalPinListSheet.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift`

**Interfaces:**
- Consomme : `PersonalPinStore`, `PersonalPin`, `Game`, `MapFocusRequest`.
- Produit : `struct PersonalPinBookView: View` — `init(store:game:isProEntitled:onSelect:onDismiss:)`, où `onSelect: (PersonalPin) -> Void`.

- [ ] **Step 1 : Écrire le carnet**

Créer `NeonCompass/Features/Map/PersonalPinBookView.swift` :

```swift
import SwiftUI

/// Le carnet — la liste des épingles de la carte affichée.
///
/// Ce qu'il apporte et qui manquait le plus : **taper une ligne ramène à
/// l'épingle**. Rien, jusqu'ici, ne permettait de retrouver un repère dont on
/// avait oublié l'emplacement.
///
/// Il ne porte PAS de `NavigationStack` quand il est posé en panneau : le
/// CLAUDE.md rappelle qu'un `ToolbarItem` sur un écran d'onglet ne s'affiche
/// nulle part. Le titre et le décompte sont donc du contenu, comme le bouton de
/// fermeture.
struct PersonalPinBookView: View {
    let store: PersonalPinStore
    let game: Game
    let isProEntitled: Bool
    let onSelect: (PersonalPin) -> Void
    let onDismiss: () -> Void

    private var pins: [PersonalPin] { store.pins(for: game) }
    private var todo: [PersonalPin] { pins.filter { !$0.isDone } }
    private var done: [PersonalPin] { pins.filter(\.isDone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if pins.isEmpty {
                ContentUnavailableView(
                    "map.pins.empty.title",
                    systemImage: "mappin.slash",
                    description: Text("map.pins.empty.message")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    if !todo.isEmpty {
                        Section(header: Text("map.pins.section.todo")) {
                            ForEach(todo) { row($0) }
                                .onDelete { delete($0, from: todo) }
                        }
                    }
                    if !done.isEmpty {
                        Section(header: Text("map.pins.section.done")) {
                            ForEach(done) { row($0) }
                                .onDelete { delete($0, from: done) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text("map.personalPins.title")
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)
            Spacer()
            // Le décompte ne s'affiche qu'en gratuit : en Pro il n'y a pas de
            // plafond, donc « 34 / ∞ » ne dirait rien.
            if !isProEntitled {
                Text(verbatim: "\(store.pins.count) / \(PersonalPinStore.freeCap)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(store.isAtCap(isProEntitled: false) ? NCColor.sunsetMagenta : .secondary)
                    .accessibilityLabel(Text("map.pins.countAccessibility \(store.pins.count) \(PersonalPinStore.freeCap)"))
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, -10)
            .accessibilityLabel(Text("poi.detail.close"))
        }
    }

    private func row(_ pin: PersonalPin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pin.iconValue.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(pin.isDone ? .secondary : NCColor.sunsetOrange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title.isEmpty ? String(localized: "map.pins.untitled") : pin.title)
                    .font(NCTypography.body)
                    .foregroundStyle(pin.isDone ? .secondary : .white)
                if !pin.note.isEmpty {
                    Text(pin.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                store.toggleDone(pin)
            } label: {
                Image(systemName: pin.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(pin.isDone ? NCColor.neonCyan : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(pin.isDone ? "map.pins.card.done" : "map.pins.card.markDone"))
        }
        .listRowBackground(Color.clear)
        // La ligne ENTIÈRE ramène à l'épingle, sauf la coche qui a sa propre
        // cible. `contentShape` est indispensable : sans elle, l'espace entre le
        // texte et la coche ne recevrait rien.
        .contentShape(.rect)
        .onTapGesture { onSelect(pin) }
    }

    private func delete(_ offsets: IndexSet, from section: [PersonalPin]) {
        for index in offsets { store.delete(section[index]) }
    }
}
```

- [ ] **Step 2 : Poser le carnet dans la fente du panneau**

Dans `NeonCompass/Features/Map/MapScreen.swift` :

Supprimer le `.sheet(isPresented: $showPersonalPinList) { PersonalPinListSheet(...) }`.

Dans la disposition **compacte**, le carnet reste une feuille (c'est ce que la largeur compacte veut) — ajouter sur `mapCanvas` :

```swift
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinBookView(
                store: personalPinStore,
                game: mapGame,
                isProEntitled: proEntitlementModel.isProEntitled,
                onSelect: { pin in
                    showPersonalPinList = false
                    focusRequest = MapFocusRequest(position: pin.position)
                    model.selection = .pin(pin)
                },
                onDismiss: { showPersonalPinList = false }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(NCColor.nightSky)
        }
```

Envelopper ce modificateur pour qu'il ne s'applique qu'en compact : le poser sur la branche compacte de `content(model:)` plutôt que sur `mapCanvas`, en l'attachant au `ZStack` extérieur de la branche compacte.

Dans la disposition **régulière**, le carnet occupe la **même fente** que la fiche. Remplacer le `ZStack(alignment: .trailing)` de la branche régulière par :

```swift
            ZStack(alignment: .trailing) {
                ZStack(alignment: .top) {
                    mapCanvas(model: model)
                    MapFilterControls(
                        model: model,
                        showPersonalPins: $showPersonalPins,
                        showPersonalPinList: $showPersonalPinList,
                        showRoutePlanner: $showRoutePlanner
                    )
                    displayControls
                }
                // Une seule colonne à droite, jamais deux : la carte est le sujet
                // de l'écran. Le carnet passe donc DEVANT la fiche, et ouvrir
                // l'un ferme l'autre.
                if showPersonalPinList {
                    PersonalPinBookView(
                        store: personalPinStore,
                        game: mapGame,
                        isProEntitled: proEntitlementModel.isProEntitled,
                        onSelect: { pin in
                            showPersonalPinList = false
                            focusRequest = MapFocusRequest(position: pin.position)
                            model.selection = .pin(pin)
                        },
                        onDismiss: { showPersonalPinList = false }
                    )
                    .frame(width: 340)
                    .containerRelativeFrame(.vertical, alignment: .center) { height, _ in height * 0.7 }
                    .transition(.move(edge: .trailing))
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .trailing, width: 340)
                }
            }
            .animation(.snappy, value: model.selection)
            .animation(.snappy, value: showPersonalPinList)
```

Et, pour que la règle « ouvrir l'un ferme l'autre » tienne dans les deux sens, ajouter sur le `ZStack` de la branche régulière :

```swift
            .onChange(of: showPersonalPinList) { _, isShown in
                if isShown { model.selection = nil }
            }
```

- [ ] **Step 3 : La puce de filtre et le glyphe du bouton**

Dans `NeonCompass/Features/Map/MapFilterControls.swift` :

Ajouter la liaison, auprès des autres :

```swift
    @Binding var showPersonalPins: Bool
```

Remplacer `favoritesButton` — le nom mentait, ce bouton n'a jamais ouvert des favoris :

```swift
    private var notebookButton: some View {
        Button {
            showPersonalPinList = true
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("map.personalPins.title"))
    }
```

et son usage dans `body` : `notebookButton`.

Ajouter la puce, dans le `VStack` des filtres, juste après `categoryChips` :

```swift
                    if showFilters {
                        categoryChips
                        // Les épingles échappaient à TOUS les filtres. C'est un
                        // `Bool` à part et non un cas de plus dans
                        // `activeCategories`, qui est un `Set<POICategory>` — y
                        // ranger une épingle serait un mensonge de type.
                        Button {
                            showPersonalPins.toggle()
                        } label: {
                            Text("map.filter.pins")
                                .font(.caption)
                                .foregroundStyle(showPersonalPins ? NCColor.sunsetOrange : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
```

Dans `MapScreen`, ajouter `@State private var showPersonalPins = true`, passer `showPersonalPins: $showPersonalPins` aux deux appels de `MapFilterControls`, et `showPersonalPins: showPersonalPins` à `TiledMapRepresentable`.

- [ ] **Step 4 : Supprimer l'ancienne liste**

```sh
git rm NeonCompass/Features/Map/PersonalPinListSheet.swift
xcodegen generate
```

- [ ] **Step 5 : Compiler**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -20
```

Attendu : compilation propre sur les deux destinations.

- [ ] **Step 6 : Commit**

```sh
git status
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
git add -A
git commit -m "feat(carte): le carnet remplace la liste, et ramène à l'épingle"
```

---

## Task 8 : Le mur du plafond, les chaînes, et la vérification

**Files:**
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consomme : `showNotebookFull`, `showPaywall` (tâche 6), `PaywallView` (existant).

- [ ] **Step 1 : Dessiner le mur**

Dans `NeonCompass/Features/Map/MapScreen.swift`, ajouter sur `mapCanvas`, à côté des autres présentations :

```swift
        // Le mur du plafond. Il DIT ce qui bloque avant de proposer l'achat —
        // une feuille d'achat qui surgirait sans explication passerait pour une
        // panne.
        .alert("map.pins.full.title", isPresented: $showNotebookFull) {
            Button("map.pins.full.upgrade") { showPaywall = true }
            Button("map.pins.full.cancel", role: .cancel) {}
        } message: {
            Text("map.pins.full.message")
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
```

- [ ] **Step 2 : Ajouter les clés au catalogue**

Écrire et lancer `$CLAUDE_JOB_DIR/tmp/add-pin-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "map.pins.untitled": {
        "en": "Untitled", "fr": "Sans nom", "es": "Sin nombre",
        "it": "Senza nome", "de": "Ohne Namen"},
    "map.pins.section.todo": {
        "en": "To do", "fr": "À faire", "es": "Pendientes",
        "it": "Da fare", "de": "Offen"},
    "map.pins.section.done": {
        "en": "Done", "fr": "Fait", "es": "Hechos",
        "it": "Fatti", "de": "Erledigt"},
    "map.pins.empty.title": {
        "en": "No pins yet", "fr": "Aucune épingle", "es": "Aún no hay pines",
        "it": "Nessun segnaposto", "de": "Noch keine Markierungen"},
    "map.pins.empty.message": {
        "en": "Press and hold anywhere on the map to drop a pin.",
        "fr": "Appuyez longuement sur la carte pour poser une épingle.",
        "es": "Mantén pulsado el mapa para colocar un pin.",
        "it": "Tieni premuto sulla mappa per posare un segnaposto.",
        "de": "Halte die Karte gedrückt, um eine Markierung zu setzen."},
    "map.pins.card.titlePlaceholder": {
        "en": "Name this pin", "fr": "Nommez cette épingle", "es": "Nombra este pin",
        "it": "Dai un nome a questo segnaposto", "de": "Markierung benennen"},
    "map.pins.card.notePlaceholder": {
        "en": "A note for later", "fr": "Une note pour plus tard", "es": "Una nota para después",
        "it": "Una nota per dopo", "de": "Eine Notiz für später"},
    "map.pins.card.markDone": {
        "en": "Mark as done", "fr": "Marquer comme fait", "es": "Marcar como hecho",
        "it": "Segna come fatto", "de": "Als erledigt markieren"},
    "map.pins.card.done": {
        "en": "Done", "fr": "Fait", "es": "Hecho",
        "it": "Fatto", "de": "Erledigt"},
    "map.pins.card.delete": {
        "en": "Delete pin", "fr": "Supprimer l'épingle", "es": "Eliminar pin",
        "it": "Elimina segnaposto", "de": "Markierung löschen"},
    "map.pins.card.deleteConfirm": {
        "en": "Delete this pin?", "fr": "Supprimer cette épingle ?", "es": "¿Eliminar este pin?",
        "it": "Eliminare questo segnaposto?", "de": "Diese Markierung löschen?"},
    "map.pins.card.cancel": {
        "en": "Cancel", "fr": "Annuler", "es": "Cancelar",
        "it": "Annulla", "de": "Abbrechen"},
    "map.pins.icon.marker": {
        "en": "Marker", "fr": "Repère", "es": "Marcador",
        "it": "Segnaposto", "de": "Markierung"},
    "map.pins.icon.vehicle": {
        "en": "Vehicle", "fr": "Véhicule", "es": "Vehículo",
        "it": "Veicolo", "de": "Fahrzeug"},
    "map.pins.icon.photo": {
        "en": "Photo spot", "fr": "Spot photo", "es": "Punto fotográfico",
        "it": "Punto foto", "de": "Fotostelle"},
    "map.pins.icon.stash": {
        "en": "Stash", "fr": "Cache", "es": "Escondite",
        "it": "Nascondiglio", "de": "Versteck"},
    "map.pins.icon.danger": {
        "en": "Danger", "fr": "Danger", "es": "Peligro",
        "it": "Pericolo", "de": "Gefahr"},
    "map.pins.icon.explore": {
        "en": "To explore", "fr": "À explorer", "es": "Por explorar",
        "it": "Da esplorare", "de": "Zu erkunden"},
    "map.pins.full.title": {
        "en": "Notebook full", "fr": "Carnet plein", "es": "Cuaderno lleno",
        "it": "Taccuino pieno", "de": "Notizbuch voll"},
    "map.pins.full.message": {
        "en": "Free notebooks hold 20 pins. Pro lifts the limit and keeps your notebook in sync across your devices.",
        "fr": "Le carnet gratuit tient vingt épingles. Pro lève la limite et garde votre carnet synchronisé entre vos appareils.",
        "es": "El cuaderno gratuito admite 20 pines. Pro elimina el límite y sincroniza tu cuaderno entre tus dispositivos.",
        "it": "Il taccuino gratuito contiene 20 segnaposti. Pro toglie il limite e sincronizza il taccuino tra i tuoi dispositivi.",
        "de": "Das kostenlose Notizbuch fasst 20 Markierungen. Pro hebt das Limit auf und hält dein Notizbuch geräteübergreifend synchron."},
    "map.pins.full.upgrade": {
        "en": "See Pro", "fr": "Voir Pro", "es": "Ver Pro",
        "it": "Scopri Pro", "de": "Pro ansehen"},
    "map.pins.full.cancel": {
        "en": "Not now", "fr": "Plus tard", "es": "Ahora no",
        "it": "Non ora", "de": "Später"},
    "map.filter.pins": {
        "en": "My pins", "fr": "Mes épingles", "es": "Mis pines",
        "it": "I miei segnaposti", "de": "Meine Markierungen"},
    "map.pins.countAccessibility %lld %lld": {
        "en": "%1$lld of %2$lld pins used",
        "fr": "%1$lld épingles sur %2$lld utilisées",
        "es": "%1$lld de %2$lld pines usados",
        "it": "%1$lld segnaposti su %2$lld usati",
        "de": "%1$lld von %2$lld Markierungen belegt"},
}

# L'alerte de création disparaît avec elle : trois clés n'ont plus d'appelant.
REMOVED = ["map.personalPins.addPrompt", "map.personalPins.save", "map.personalPins.cancel"]

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

for key in REMOVED:
    catalog["strings"].pop(key, None)

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(REMOVED)} retirées, {len(catalog['strings'])} au total")
```

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-pin-keys.py"
```

Attendu : `24 clés ajoutées, 3 retirées, 213 au total`.

- [ ] **Step 3 : Lancer toute la suite, sur les deux appareils**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -40
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -20
```

Attendu : suite verte, dont `LocalizationCoverageTests` (les cinq langues, les spécificateurs de format concordants) et `PersonalPinStoreTests`.

- [ ] **Step 4 : Vérifier que le catalogue n'a pas été réécrit par le test**

```sh
git diff --stat NeonCompass/Resources/Localizable.xcstrings
```

Si le diff porte des souches à suffixe `%@` sans traduction, elles viennent de l'extraction automatique : les retirer avant de commiter, en relançant le script de l'étape 2 sur le fichier restauré.

- [ ] **Step 5 : Commit**

```sh
git add -A
git commit -m "feat(carte): le plafond du carnet gratuit, et ses vingt-quatre chaînes"
```

---

## Self-review

**Couverture de la spec.** Chaque section de la spec pointe vers une tâche : le modèle et les icônes → tâche 1 ; le magasin et le plafond → tâche 2 ; la sélection → tâche 3 ; le rendu, la portée par carte, les zones de frappe → tâche 4 ; `focus(on:)` → tâche 5 ; la fiche → tâche 6 ; le carnet et la puce de filtre → tâche 7 ; le mur, la localisation, la vérification → tâche 8. La règle de déclassement est testée en tâche 2 (`anOverCapNotebookStaysEditable`). Le chantier 2 (synchro) est hors de ce plan par construction.

**Cohérence des types.** `PersonalPinStore.create(at:game:isProEntitled:)` porte la même signature dans les tâches 2, 3, 6 et 7. `MapSelection.pin` / `.poi` sont lus de la même façon en tâches 3, 6 et 7. `DroppedPinView.isDone` a une valeur par défaut, donc l'appel communautaire de `ContributionAnnotationView` reste valide sans modification. `MapFocusRequest(position:)` est construit en tâche 7 avec le même initialiseur que celui défini en tâche 5.

**Points d'attention pour l'exécutant.**

1. La branche compacte et la branche régulière de `content(model:)` ne se ressemblent qu'en apparence : le carnet y est une feuille d'un côté, un panneau de l'autre, et seule la seconde partage sa fente avec la fiche.
2. `String(localized:)` sur une clé absente du catalogue renvoie la clé elle-même sans erreur de compilation. Les tâches 4, 6 et 7 compilent donc avant que la tâche 8 n'ajoute les chaînes — mais l'app affiche `map.pins.untitled` en toutes lettres jusque-là. C'est attendu.
3. `git status` avant chaque commit : `xcodebuild test` réécrit `Localizable.xcstrings`.
