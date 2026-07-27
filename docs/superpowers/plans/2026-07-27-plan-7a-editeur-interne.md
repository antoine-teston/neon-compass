# Plan 7a — Mode éditeur interne

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser, déplacer et supprimer des POI au doigt depuis un build debug, et matérialiser ces gestes en fichiers `content/poi/*.json` par une commande sur le Mac.

**Architecture:** Le téléphone écrit des brouillons dans une collection Firestore `editor_drafts` que rien d'autre ne lit — la persistance hors-ligne du SDK sert de file. Sur le Mac, `content-cli pull-drafts` lit les brouillons non appliqués, les transforme en fichiers via une fonction pure, et les marque appliqués. L'identifiant `poi_*` est frappé une seule fois à ce moment-là, via la clé d'identité `processedFrom` qui donne l'idempotence.

**Tech Stack:** Swift 6 / SwiftUI / Observation / Swift Testing ; Node ESM / `node:test` ; Firestore.

**Spec:** `docs/superpowers/specs/2026-07-27-editeur-interne-design.md`

## Global Constraints

- **Build debug uniquement** : tout `Core/Editor/` et `Features/Editor/` est encadré par `#if DEBUG`. Rien de l'éditeur ne doit exister dans le binaire soumis.
- **Leonida uniquement** : l'éditeur refuse de s'armer quand `MapGame.reference` est affichée. Les brouillons visent toujours `content/poi/`, jamais `content/poi-gtav/`.
- **Swift 6, concurrence stricte** (`SWIFT_STRICT_CONCURRENCY: complete`). SwiftUI seul ; UIKit uniquement là où il est déjà (`MapScrollView.swift`).
- **Firebase derrière un protocole** (CLAUDE.md) : les features ne référencent jamais `FirebaseFirestore` directement.
- **Tests** : Swift Testing (`import Testing`) côté app, `node:test` côté outils. Pas de test d'UI.
- **Écart assumé à CLAUDE.md, à mentionner en revue** : les libellés de l'éditeur sont des littéraux français, pas des clés du String Catalog. L'éditeur n'est jamais livré ; lui écrire cinq traductions serait du travail pur perte. `LocalizationCoverageTests` ne vérifie que les clés présentes dans le catalogue, il ne scanne pas les sources — rien ne casse.
- **Écart assumé à la spec (D5)** : le déplacement ne se fait pas en traînant le pin (le glissement se bat avec le pan de l'`UIScrollView`) mais en deux temps — « Déplacer » arme le déplacement, l'appui long suivant pose la nouvelle position. Même geste que la création, aucun conflit, et plus précis à bout de bras.
- **Commandes** : `Scripts/test.sh` (génère le projet + tests), `Scripts/build.sh`. Côté outils : `cd tools/content-cli && node --test`.

---

### Task 1 : Le brouillon et son entrepôt

**Files:**
- Create: `NeonCompass/Core/Editor/EditorDraft.swift`
- Create: `NeonCompass/Core/Editor/EditorDraftStore.swift`
- Test: `NeonCompassTests/Editor/EditorDraftTests.swift`

**Interfaces:**
- Produces: `EditorDraft` (struct `Codable, Equatable, Sendable, Identifiable`), ses fabriques `create`/`move`/`delete`/`adopting`, et le protocole `EditorDraftStore` (`save(_:) throws`, `waitForDelivery() async throws`).

- [ ] **Step 1 : Écrire le test qui échoue**

`NeonCompassTests/Editor/EditorDraftTests.swift` :

```swift
#if DEBUG
import Testing
import Foundation
@testable import NeonCompass

struct EditorDraftTests {
    private static let date = Date(timeIntervalSince1970: 1_763_000_000)

    @Test func createCarriesCategoryAndPosition() {
        let draft = EditorDraft.create(
            id: "u1",
            category: .collectible,
            at: NormalizedPoint(x: 0.25, y: 0.5),
            capturedAt: Self.date
        )
        #expect(draft.kind == .create)
        #expect(draft.category == .collectible)
        #expect(draft.position == NormalizedPoint(x: 0.25, y: 0.5))
        #expect(draft.targetPOIID == nil)
        #expect(draft.title == nil)
    }

    @Test func moveCarriesTargetAndDestination() {
        let draft = EditorDraft.move(
            id: "u2",
            poiID: "poi_leonida_collectible_ab12cd34",
            to: NormalizedPoint(x: 0.1, y: 0.2),
            capturedAt: Self.date
        )
        #expect(draft.kind == .move)
        #expect(draft.targetPOIID == "poi_leonida_collectible_ab12cd34")
        #expect(draft.position == NormalizedPoint(x: 0.1, y: 0.2))
        #expect(draft.category == nil)
    }

    @Test func deleteCarriesTargetOnly() {
        let draft = EditorDraft.delete(id: "u3", poiID: "poi_x", capturedAt: Self.date)
        #expect(draft.kind == .delete)
        #expect(draft.targetPOIID == "poi_x")
        #expect(draft.position == nil)
    }

    /// L'adoption est la passerelle communauté → éditorial : la position et le
    /// titre proposés sont repris tels quels, et l'origine est conservée pour
    /// que `sources` puisse la citer.
    @Test func adoptingACommunitySpotPrefillsEverything() {
        let spot = Contribution(
            id: "c42",
            authorUid: "uid",
            authorHandle: "handle",
            category: .safehouse,
            title: "Planque sous le pont",
            languageCode: "fr",
            position: NormalizedPoint(x: 0.7, y: 0.3),
            status: .approved,
            upvotes: 12,
            downvotes: 0
        )
        let draft = EditorDraft.adopting(spot, id: "u4", capturedAt: Self.date)
        #expect(draft.kind == .create)
        #expect(draft.category == .safehouse)
        #expect(draft.position == NormalizedPoint(x: 0.7, y: 0.3))
        #expect(draft.title == "Planque sous le pont")
        #expect(draft.sourceContributionID == "c42")
    }

    @Test func roundTripsThroughJSON() throws {
        let draft = EditorDraft.create(
            id: "u5",
            category: .vehicle,
            at: NormalizedPoint(x: 0.5, y: 0.5),
            capturedAt: Self.date
        )
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(EditorDraft.self, from: data)
        #expect(decoded == draft)
    }
}
#endif
```

- [ ] **Step 2 : Lancer le test, vérifier qu'il échoue**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/EditorDraftTests`
Expected: échec de compilation — `cannot find 'EditorDraft' in scope`.

- [ ] **Step 3 : Écrire `EditorDraft.swift`**

```swift
#if DEBUG
import Foundation

/// Une opération capturée au doigt, en attente de matérialisation en fichier
/// `content/poi/*.json` par `content-cli pull-drafts`.
///
/// Le brouillon naît avec un UUID, jamais avec un identifiant `poi_*` : celui-ci
/// est frappé une seule fois, au Mac, quand le contenu est complet — voir la
/// décision D4 de la spec et `tools/basemap/gtav-poi-ids.mjs`.
struct EditorDraft: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case create, move, delete
    }

    let id: String
    let kind: Kind
    /// Renseignée pour `create` seulement : un déplacement ou une suppression
    /// n'a pas à redire la catégorie du POI visé.
    let category: POICategory?
    /// Destination pour `create` et `move`, absente pour `delete`.
    let position: NormalizedPoint?
    /// Identifiant du POI visé, pour `move` et `delete`.
    let targetPOIID: String?
    /// Facultatif : la capture éclair n'en demande pas. La rédaction se fait au Mac.
    let title: String?
    /// Contribution communautaire adoptée, le cas échéant — citée dans `sources`.
    let sourceContributionID: String?
    let capturedAt: Date

    static func create(
        id: String,
        category: POICategory,
        at position: NormalizedPoint,
        title: String? = nil,
        sourceContributionID: String? = nil,
        capturedAt: Date
    ) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .create,
            category: category,
            position: position,
            targetPOIID: nil,
            title: title,
            sourceContributionID: sourceContributionID,
            capturedAt: capturedAt
        )
    }

    static func move(id: String, poiID: String, to position: NormalizedPoint, capturedAt: Date) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .move,
            category: nil,
            position: position,
            targetPOIID: poiID,
            title: nil,
            sourceContributionID: nil,
            capturedAt: capturedAt
        )
    }

    static func delete(id: String, poiID: String, capturedAt: Date) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .delete,
            category: nil,
            position: nil,
            targetPOIID: poiID,
            title: nil,
            sourceContributionID: nil,
            capturedAt: capturedAt
        )
    }

    /// Passerelle communauté → éditorial : un spot approuvé devient un brouillon
    /// pré-rempli. C'est ce qui fait que le repérage de la foule finit par
    /// compter dans la progression et les défis.
    static func adopting(_ spot: Contribution, id: String, capturedAt: Date) -> EditorDraft {
        create(
            id: id,
            category: spot.category,
            at: spot.position,
            title: spot.title,
            sourceContributionID: spot.id,
            capturedAt: capturedAt
        )
    }
}
#endif
```

- [ ] **Step 4 : Écrire `EditorDraftStore.swift`**

```swift
#if DEBUG
import Foundation

/// Entrepôt de brouillons. Firebase reste derrière ce protocole (CLAUDE.md) :
/// `EditorModel` ne connaît que lui, et les tests lui substituent un double
/// en mémoire.
protocol EditorDraftStore: Sendable {
    /// Persiste localement et rend la main immédiatement — l'envoi réseau est
    /// asynchrone et peut n'arriver que bien plus tard. Ne jamais attendre ici :
    /// la capture doit tenir en moins de trois secondes, réseau ou pas.
    func save(_ draft: EditorDraft) throws

    /// Rend la main quand toutes les écritures en attente ont été acquittées par
    /// le serveur. Ne rend jamais la main tant qu'on est hors-ligne — c'est
    /// voulu : c'est exactement ce que le bandeau affiche.
    func waitForDelivery() async throws
}
#endif
```

- [ ] **Step 5 : Lancer le test, vérifier qu'il passe**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/EditorDraftTests`
Expected: PASS, 5 tests.

- [ ] **Step 6 : Commit**

```bash
git add NeonCompass/Core/Editor NeonCompassTests/Editor
git commit -m "feat(editor): modèle de brouillon et protocole d'entrepôt"
```

---

### Task 2 : L'entrepôt Firestore et sa règle de sécurité

**Files:**
- Create: `NeonCompass/Core/Editor/FirestoreEditorDraftStore.swift`
- Modify: `firestore.rules`

**Interfaces:**
- Consumes: `EditorDraft`, `EditorDraftStore` (Task 1).
- Produces: `FirestoreEditorDraftStore()` — implémentation concrète injectée par `MapScreen` (Task 5).

Pas de test unitaire sur cette classe : elle n'est qu'un adaptateur vers le SDK, comme `FirestoreContentRepository` et `FirestoreContributionRepository` qui n'en ont pas non plus. Le comportement testable vit derrière le protocole, dans `EditorModel`.

- [ ] **Step 1 : Écrire l'adaptateur**

```swift
#if DEBUG
import FirebaseFirestore
import Foundation

/// Écrit dans `editor_drafts`, collection qu'aucun chemin de contenu de l'app ne
/// lit et que les Security Rules réservent à un seul UID.
///
/// `setData(from:)` rend la main dès l'écriture locale : le SDK persiste sur
/// disque et rejoue la file au retour du réseau. C'est ce qui rend la capture
/// utilisable dans un sous-sol, sans une ligne de code de notre part.
final class FirestoreEditorDraftStore: EditorDraftStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func save(_ draft: EditorDraft) throws {
        try firestore.collection("editor_drafts").document(draft.id).setData(from: draft)
    }

    func waitForDelivery() async throws {
        try await firestore.waitForPendingWrites()
    }
}
#endif
```

- [ ] **Step 2 : Ajouter la règle**

Dans `firestore.rules`, à côté du bloc `contributions`, avant le `match /{document=**}` final :

```
    // Brouillons du mode éditeur interne (build debug uniquement). Réservés à un
    // UID unique : l'auteur du projet. Tant que l'UID n'est pas renseigné,
    // personne ne passe — un défaut fermé, pas ouvert. L'UID se relève au premier
    // armement de l'éditeur, le bandeau l'affiche.
    match /editor_drafts/{id} {
      allow read, write: if request.auth != null
        && request.auth.uid == 'REMPLACER_PAR_UID_EDITEUR';
    }
```

- [ ] **Step 3 : Vérifier que le projet compile**

Run: `Scripts/build.sh`
Expected: BUILD SUCCEEDED pour les deux schémas.

- [ ] **Step 4 : Commit**

```bash
git add NeonCompass/Core/Editor/FirestoreEditorDraftStore.swift firestore.rules
git commit -m "feat(editor): entrepôt Firestore et règle editor_drafts réservée à un UID"
```

Note : ne pas déployer les règles maintenant. `node cli.js rules-diff` puis `deploy-rules` une fois l'UID renseigné (Task 8).

---

### Task 3 : `EditorModel` — armement, capture, déplacement, adoption

**Files:**
- Create: `NeonCompass/Features/Editor/EditorModel.swift`
- Test: `NeonCompassTests/Editor/EditorModelTests.swift`

**Interfaces:**
- Consumes: `EditorDraft`, `EditorDraftStore` (Task 1), `MapGame`, `POICategory`, `NormalizedPoint`, `Contribution`.
- Produces: `EditorModel` avec `isArmed`, `draftPins: [DraftPin]`, `undeliveredCount`, `pendingCapture: NormalizedPoint?`, `pendingMovePOIID: String?`, et les méthodes `canArm(on:)`, `setArmed(_:on:)`, `capture(category:at:)`, `beginMove(poiID:)`, `completeMove(at:)`, `delete(poiID:)`, `adopt(_:)`.
- Produces aussi : `DraftPin` (Task 5 le consomme pour l'affichage).

- [ ] **Step 1 : Écrire le test qui échoue**

`NeonCompassTests/Editor/EditorModelTests.swift` :

```swift
#if DEBUG
import Testing
import Foundation
@testable import NeonCompass

/// Double en mémoire : `EditorModel` ne connaît que le protocole, donc aucun
/// test n'a besoin de Firestore.
private final class SpyDraftStore: EditorDraftStore, @unchecked Sendable {
    private(set) var saved: [EditorDraft] = []
    private(set) var deliveryWaits = 0
    var deliveryError: Error?

    func save(_ draft: EditorDraft) throws { saved.append(draft) }

    func waitForDelivery() async throws {
        deliveryWaits += 1
        if let deliveryError { throw deliveryError }
    }
}

private struct Ids {
    static func sequence() -> @Sendable () -> String {
        let counter = Counter()
        return { counter.next() }
    }

    final class Counter: @unchecked Sendable {
        private var value = 0
        func next() -> String {
            value += 1
            return "u\(value)"
        }
    }
}

@MainActor
struct EditorModelTests {
    private static let date = Date(timeIntervalSince1970: 1_763_000_000)

    private func makeModel(store: SpyDraftStore) -> EditorModel {
        EditorModel(store: store, makeID: Ids.sequence(), now: { Self.date })
    }

    @Test func refusesToArmOnTheReferenceMap() {
        let model = makeModel(store: SpyDraftStore())
        #expect(model.canArm(on: .leonida))
        #expect(!model.canArm(on: .reference))

        model.setArmed(true, on: .reference)
        #expect(!model.isArmed)

        model.setArmed(true, on: .leonida)
        #expect(model.isArmed)
    }

    /// Basculer sur la carte de référence pendant que l'éditeur est armé doit le
    /// désarmer : sinon un appui long y créerait un POI aux coordonnées d'une
    /// autre carte.
    @Test func disarmsWhenTheMapSwitchesToReference() {
        let model = makeModel(store: SpyDraftStore())
        model.setArmed(true, on: .leonida)
        model.mapChanged(to: .reference)
        #expect(!model.isArmed)
    }

    @Test func captureSavesADraftAndShowsItsPin() throws {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        model.capture(category: .collectible, at: NormalizedPoint(x: 0.4, y: 0.6))

        #expect(store.saved.count == 1)
        #expect(store.saved[0].kind == .create)
        #expect(store.saved[0].category == .collectible)
        #expect(model.draftPins.count == 1)
        #expect(model.draftPins[0].position == NormalizedPoint(x: 0.4, y: 0.6))
        #expect(model.draftPins[0].category == .collectible)
    }

    @Test func captureIsIgnoredWhenNotArmed() {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.capture(category: .collectible, at: NormalizedPoint(x: 0.4, y: 0.6))
        #expect(store.saved.isEmpty)
    }

    /// Le déplacement se fait en deux temps : « Déplacer » arme, l'appui long
    /// suivant pose. Tant qu'il n'est pas posé, aucun brouillon n'existe.
    @Test func moveTakesTwoSteps() {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        model.beginMove(poiID: "poi_a")
        #expect(model.pendingMovePOIID == "poi_a")
        #expect(store.saved.isEmpty)

        model.completeMove(at: NormalizedPoint(x: 0.9, y: 0.1))
        #expect(model.pendingMovePOIID == nil)
        #expect(store.saved.count == 1)
        #expect(store.saved[0].kind == .move)
        #expect(store.saved[0].targetPOIID == "poi_a")
        #expect(store.saved[0].position == NormalizedPoint(x: 0.9, y: 0.1))
    }

    /// Un appui long alors qu'un déplacement est armé pose la destination, il ne
    /// crée pas un nouveau POI.
    @Test func longPressCompletesAPendingMoveRatherThanCapturing() {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)
        model.beginMove(poiID: "poi_a")

        #expect(model.handleLongPress(at: NormalizedPoint(x: 0.3, y: 0.3)) == .completedMove)
        #expect(store.saved.count == 1)
        #expect(store.saved[0].kind == .move)
        #expect(model.pendingCapture == nil)
    }

    @Test func longPressWithoutPendingMoveOpensTheCategoryGrid() {
        let model = makeModel(store: SpyDraftStore())
        model.setArmed(true, on: .leonida)
        #expect(model.handleLongPress(at: NormalizedPoint(x: 0.3, y: 0.3)) == .askedForCategory)
        #expect(model.pendingCapture == NormalizedPoint(x: 0.3, y: 0.3))
    }

    @Test func deleteSavesATombstoneDraft() {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        model.delete(poiID: "poi_b")

        #expect(store.saved.count == 1)
        #expect(store.saved[0].kind == .delete)
        #expect(store.saved[0].targetPOIID == "poi_b")
    }

    @Test func adoptCopiesTheCommunitySpot() {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        let spot = Contribution(
            id: "c7",
            authorUid: "uid",
            authorHandle: "h",
            category: .activity,
            title: "Rampe derrière l'entrepôt",
            languageCode: "fr",
            position: NormalizedPoint(x: 0.2, y: 0.8),
            status: .approved,
            upvotes: 4,
            downvotes: 1
        )
        model.adopt(spot)

        #expect(store.saved.count == 1)
        #expect(store.saved[0].sourceContributionID == "c7")
        #expect(store.saved[0].title == "Rampe derrière l'entrepôt")
        #expect(model.draftPins.count == 1)
    }

    @Test func undeliveredCountFallsToZeroOnceTheServerAcknowledges() async {
        let store = SpyDraftStore()
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        model.capture(category: .event, at: NormalizedPoint(x: 0.5, y: 0.5))
        #expect(model.undeliveredCount == 1)

        await model.awaitDelivery()
        #expect(model.undeliveredCount == 0)
        #expect(store.deliveryWaits == 1)
    }

    /// Hors-ligne, l'accusé n'arrive jamais : le compteur doit RESTER à son
    /// niveau, surtout pas retomber à zéro et laisser croire que c'est parti.
    @Test func undeliveredCountSurvivesADeliveryFailure() async {
        let store = SpyDraftStore()
        store.deliveryError = URLError(.notConnectedToInternet)
        let model = makeModel(store: store)
        model.setArmed(true, on: .leonida)

        model.capture(category: .event, at: NormalizedPoint(x: 0.5, y: 0.5))
        await model.awaitDelivery()
        #expect(model.undeliveredCount == 1)
    }
}
#endif
```

- [ ] **Step 2 : Lancer le test, vérifier qu'il échoue**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/EditorModelTests`
Expected: échec de compilation — `cannot find 'EditorModel' in scope`.

- [ ] **Step 3 : Écrire `DraftPin`**

`NeonCompass/Core/Map/DraftPin.swift` — délibérément **hors** `#if DEBUG` pour que `MapScrollView` n'ait pas à porter de compilation conditionnelle. En Release la liste est simplement toujours vide.

```swift
import Foundation

/// Pin d'un brouillon d'éditeur, rendu en contour pointillé pour se distinguer
/// d'un POI publié et d'un spot communautaire.
///
/// Ce type n'est pas conditionné à DEBUG, contrairement au reste de l'éditeur :
/// `MapScrollView` le reçoit dans une liste qui, en Release, est toujours vide.
/// Le prix est un type inerte de six lignes ; le bénéfice est zéro `#if` dans le
/// moteur de carte, qui est la pièce la plus délicate du dépôt.
struct DraftPin: Identifiable, Equatable, Sendable {
    let id: String
    let position: NormalizedPoint
    let category: POICategory
}
```

- [ ] **Step 4 : Écrire `EditorModel`**

```swift
#if DEBUG
import Foundation
import Observation

@Observable
@MainActor
final class EditorModel {
    /// Ce qu'un appui long a effectivement déclenché — le rendre explicite évite
    /// à la vue de redevenir la place où la règle de geste se décide.
    enum LongPressOutcome: Equatable {
        case ignored
        case askedForCategory
        case completedMove
    }

    private(set) var isArmed = false
    private(set) var draftPins: [DraftPin] = []
    private(set) var undeliveredCount = 0
    /// Position en attente d'une catégorie : non nil pendant que la grille est
    /// ouverte.
    var pendingCapture: NormalizedPoint?
    private(set) var pendingMovePOIID: String?

    private let store: EditorDraftStore
    private let makeID: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(store: EditorDraftStore, makeID: @escaping @Sendable () -> String = { UUID().uuidString }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.makeID = makeID
        self.now = now
    }

    /// L'éditeur ne s'arme que sur la carte du jeu à venir. La carte de référence
    /// n'est là que pour donner du volume explorable avant la sortie : y poser du
    /// contenu éditorial n'aurait aucun sens, et les coordonnées ne seraient pas
    /// comparables.
    func canArm(on game: MapGame) -> Bool { game == .leonida }

    func setArmed(_ armed: Bool, on game: MapGame) {
        isArmed = armed && canArm(on: game)
        if !isArmed { cancelPending() }
    }

    func mapChanged(to game: MapGame) {
        guard !canArm(on: game) else { return }
        isArmed = false
        cancelPending()
    }

    func handleLongPress(at position: NormalizedPoint) -> LongPressOutcome {
        guard isArmed else { return .ignored }
        if pendingMovePOIID != nil {
            completeMove(at: position)
            return .completedMove
        }
        pendingCapture = position
        return .askedForCategory
    }

    func capture(category: POICategory, at position: NormalizedPoint) {
        guard isArmed else { return }
        let draft = EditorDraft.create(id: makeID(), category: category, at: position, capturedAt: now())
        record(draft, pin: DraftPin(id: draft.id, position: position, category: category))
        pendingCapture = nil
    }

    func beginMove(poiID: String) {
        guard isArmed else { return }
        pendingMovePOIID = poiID
    }

    func completeMove(at position: NormalizedPoint) {
        guard isArmed, let poiID = pendingMovePOIID else { return }
        let draft = EditorDraft.move(id: makeID(), poiID: poiID, to: position, capturedAt: now())
        record(draft, pin: nil)
        pendingMovePOIID = nil
    }

    func delete(poiID: String) {
        guard isArmed else { return }
        record(EditorDraft.delete(id: makeID(), poiID: poiID, capturedAt: now()), pin: nil)
    }

    func adopt(_ spot: Contribution) {
        guard isArmed else { return }
        let draft = EditorDraft.adopting(spot, id: makeID(), capturedAt: now())
        record(draft, pin: DraftPin(id: draft.id, position: spot.position, category: spot.category))
    }

    func cancelPending() {
        pendingCapture = nil
        pendingMovePOIID = nil
    }

    /// Attend l'accusé de réception du serveur. En cas d'échec — hors-ligne, le
    /// cas nominal en session de jeu — le compteur reste à son niveau : afficher
    /// zéro laisserait croire que tout est parti.
    func awaitDelivery() async {
        do {
            try await store.waitForDelivery()
            undeliveredCount = 0
        } catch {
            // Rien : le compteur garde sa valeur, le bandeau continue d'annoncer
            // ce qui reste à envoyer.
        }
    }

    private func record(_ draft: EditorDraft, pin: DraftPin?) {
        do {
            try store.save(draft)
            undeliveredCount += 1
            if let pin { draftPins.append(pin) }
        } catch {
            print("EditorModel: brouillon non persisté \(draft.id): \(error)")
        }
    }
}
#endif
```

- [ ] **Step 5 : Lancer le test, vérifier qu'il passe**

Run: `Scripts/test.sh -only-testing:NeonCompassTests/EditorModelTests`
Expected: PASS, 11 tests.

- [ ] **Step 6 : Commit**

```bash
git add NeonCompass/Features/Editor NeonCompass/Core/Map/DraftPin.swift NeonCompassTests/Editor/EditorModelTests.swift
git commit -m "feat(editor): modèle d'édition — armement, capture, déplacement en deux temps, adoption"
```

---

### Task 4 : L'interface — grille de catégories et bandeau

**Files:**
- Create: `NeonCompass/Features/Editor/EditorCategoryGrid.swift`
- Create: `NeonCompass/Features/Editor/EditorBanner.swift`

**Interfaces:**
- Consumes: `EditorModel` (Task 3), `POIPinPalette`, `NCColor`.
- Produces: `EditorCategoryGrid(onPick:onCancel:)` et `EditorBanner(model:uid:)`.

Aucun test : ce sont deux vues sans logique. Ce qu'elles décident est déjà testé dans `EditorModel`.

- [ ] **Step 1 : Écrire la grille**

```swift
#if DEBUG
import SwiftUI

/// Grille des six catégories, présentée sous le doigt après un appui long.
/// Un tap suffit : ni champ texte ni confirmation — c'est le geste des trois
/// secondes, pensé pour ne pas quitter le jeu des yeux.
struct EditorCategoryGrid: View {
    let onPick: (POICategory) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(spacing: 16) {
            Text("Catégorie")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(POICategory.allCases, id: \.self) { category in
                    Button {
                        onPick(category)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: POIPinPalette.symbol(for: category))
                                .font(.system(size: 22, weight: .bold))
                            Text(label(for: category))
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(POIPinPalette.color(for: category, style: .neon).opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Annuler", action: onCancel)
                .foregroundStyle(NCColor.neonCyan)
        }
        .padding(20)
        .presentationDetents([.height(360)])
        .presentationBackground(.thinMaterial)
    }

    /// Littéraux français assumés : l'éditeur n'est jamais livré, lui écrire
    /// cinq traductions serait du travail pur perte (cf. Global Constraints).
    private func label(for category: POICategory) -> String {
        switch category {
        case .landmark: "Lieu"
        case .collectible: "Collectible"
        case .activity: "Activité"
        case .safehouse: "Planque"
        case .vehicle: "Véhicule"
        case .event: "Événement"
        }
    }
}
#endif
```

- [ ] **Step 2 : Écrire le bandeau**

```swift
#if DEBUG
import SwiftUI

/// Bandeau d'état de l'éditeur. Porte le marqueur que la vérification de
/// pré-soumission cherche dans le binaire Release (Task 8) : si cette chaîne
/// s'y trouve, c'est que l'éditeur a fui hors du build debug.
struct EditorBanner: View {
    let draftCount: Int
    let undeliveredCount: Int
    let uid: String?
    let pendingMove: Bool

    static let marker = "NCEditorArmedMarker"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pendingMove ? "Déplacement : appui long sur la nouvelle position" : "Éditeur armé — \(draftCount) brouillons")
                .font(.caption.weight(.semibold))
            if undeliveredCount > 0 {
                Text("\(undeliveredCount) en attente d'envoi")
                    .font(.caption2)
                    .foregroundStyle(NCColor.sunsetOrange)
            }
            // Affiché pour être recopié dans firestore.rules au premier armement.
            if let uid {
                Text(uid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityIdentifier(Self.marker)
    }
}
#endif
```

- [ ] **Step 3 : Vérifier que ça compile**

Run: `Scripts/build.sh`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4 : Commit**

```bash
git add NeonCompass/Features/Editor
git commit -m "feat(editor): grille de catégories et bandeau d'état"
```

---

### Task 5 : Brancher l'éditeur sur la carte

**Files:**
- Modify: `NeonCompass/Features/Map/MapDisplayControls.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/Core/Map/MapScrollView.swift`

**Interfaces:**
- Consumes: `EditorModel`, `EditorCategoryGrid`, `EditorBanner`, `DraftPin`.
- Produces: rien pour les tâches suivantes.

- [ ] **Step 1 : Ajouter les pins de brouillon au moteur de carte**

Dans `MapScrollView.swift`, ajouter la propriété à `MapContentSwiftUIView` (après `communitySpots`) :

```swift
    let draftPins: [DraftPin]
```

et son rendu, à la fin du `ZStack` de `body`, après le `ForEach(communitySpots)` :

```swift
            ForEach(draftPins) { pin in
                Image(systemName: POIPinPalette.symbol(for: pin.category))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(POIPinPalette.color(for: pin.category, style: style).opacity(0.4))
                            .overlay(
                                // Pointillé : un brouillon se distingue d'un POI
                                // publié au premier coup d'œil, ce qui est tout
                                // l'intérêt de l'afficher.
                                Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            )
                    )
                    .scaleEffect(pinScale)
                    .position(MapGeometry.contentPoint(for: pin.position, manifest: manifest))
                    .accessibilityLabel(Text("Brouillon"))
            }
```

Puis la même propriété sur `TiledMapRepresentable` (après `communitySpots`) et son passage dans `makeContent` :

```swift
    let draftPins: [DraftPin]
```
```swift
            communitySpots: communitySpots,
            draftPins: draftPins,
```

- [ ] **Step 2 : Ajouter l'interrupteur d'armement**

Dans `MapDisplayControls.swift`, ajouter les propriétés et le bouton :

```swift
#if DEBUG
    /// Nil quand l'éditeur n'est pas disponible sur la carte affichée.
    var editorArmed: Binding<Bool>?
#endif
```

et, dans le `VStack` du `body`, après le bloc `styleButton` :

```swift
#if DEBUG
                if let editorArmed {
                    Button {
                        withAnimation(.snappy) { editorArmed.wrappedValue.toggle() }
                    } label: {
                        Image(systemName: editorArmed.wrappedValue ? "pencil.circle.fill" : "pencil.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(editorArmed.wrappedValue ? NCColor.sunsetOrange : .white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(Text("Mode éditeur"))
                }
#endif
```

- [ ] **Step 3 : Brancher `MapScreen`**

Dans `MapScreen.swift` :

a) l'état, après `@State private var remotePOIs`:

```swift
#if DEBUG
    @State private var editorModel = EditorModel(store: FirestoreEditorDraftStore())
#endif
```

b) le passage à `MapDisplayControls`, dans `displayControls` :

```swift
    private var displayControls: some View {
        var controls = MapDisplayControls(game: $mapGame, style: $mapStyle)
#if DEBUG
        if editorModel.canArm(on: mapGame) {
            controls.editorArmed = Binding(
                get: { editorModel.isArmed },
                set: { editorModel.setArmed($0, on: mapGame) }
            )
        }
#endif
        return controls
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 76)
    }
```

c) la règle de geste, dans le `onLongPress` passé à `TiledMapRepresentable` — l'éditeur armé prend la main, sinon le comportement existant est intact :

```swift
                onLongPress: { canvasPoint in
                    let normalized = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
#if DEBUG
                    if editorModel.handleLongPress(at: normalized) != .ignored { return }
#endif
                    pendingPinLocation = normalized
                    showLongPressMenu = true
                },
```

d) `draftPins:` dans l'appel à `TiledMapRepresentable`, après `communitySpots:` :

```swift
#if DEBUG
                draftPins: editorModel.draftPins,
#else
                draftPins: [],
#endif
```

e) la grille et le bandeau, en overlay sur `mapCanvas`, et le désarmement au changement de carte. Dans `.onChange(of: mapGame)` existant, ajouter en première ligne du corps :

```swift
#if DEBUG
            editorModel.mapChanged(to: newGame)
#endif
```

et, après le dernier modificateur de `mapCanvas` :

```swift
#if DEBUG
        .overlay(alignment: .top) {
            if editorModel.isArmed {
                EditorBanner(
                    draftCount: editorModel.draftPins.count,
                    undeliveredCount: editorModel.undeliveredCount,
                    uid: authModel.userID,
                    pendingMove: editorModel.pendingMovePOIID != nil
                )
                .padding(.top, 60)
                .task(id: editorModel.undeliveredCount) { await editorModel.awaitDelivery() }
            }
        }
        .sheet(item: Binding(
            get: { editorModel.pendingCapture.map { EditorCaptureBox(location: $0) } },
            set: { editorModel.pendingCapture = $0?.location }
        )) { box in
            EditorCategoryGrid(
                onPick: { editorModel.capture(category: $0, at: box.location) },
                onCancel: { editorModel.pendingCapture = nil }
            )
        }
#endif
```

et le petit boîtier d'identité, à côté de `ContributionLocationBox` en bas du fichier :

```swift
#if DEBUG
private struct EditorCaptureBox: Identifiable {
    let location: NormalizedPoint
    var id: String { "\(location.x)-\(location.y)" }
}
#endif
```

- [ ] **Step 4 : Ajouter « Déplacer » et « Supprimer » au menu d'un pin**

`POIDetailView` est la fiche ouverte au tap d'un POI. Y ajouter, sous `#if DEBUG`, deux actions quand l'éditeur est armé. Dans `MapScreen`, la fiche est construite à deux endroits (compact et régulier) : ajouter le même bloc aux deux, en passant deux fermetures optionnelles à `POIDetailView` :

```swift
#if DEBUG
                    onEditorMove: editorModel.isArmed ? { editorModel.beginMove(poiID: poi.id); model.selectedPOI = nil } : nil,
                    onEditorDelete: editorModel.isArmed ? { editorModel.delete(poiID: poi.id); model.selectedPOI = nil } : nil,
#endif
```

et dans `POIDetailView`, déclarer les deux propriétés sous `#if DEBUG` (valeur par défaut `nil`) et rendre deux boutons quand elles sont non nil — « Déplacer ce pin » et « Supprimer ce pin », ce dernier en `role: .destructive` avec un `confirmationDialog`.

- [ ] **Step 5 : Ajouter « Adopter » sur un spot communautaire**

Dans `ContributionAnnotationView`, ajouter de la même façon une fermeture `onAdopt: (() -> Void)?` sous `#if DEBUG`, rendue en entrée de menu « Adopter », et la câbler depuis `MapScreen` sur `editorModel.adopt(spot)`.

- [ ] **Step 6 : Vérifier que tout compile et que rien n'a régressé**

Run: `Scripts/test.sh`
Expected: BUILD SUCCEEDED, tous les tests au vert (168 existants + 16 nouveaux).

- [ ] **Step 7 : Vérification manuelle sur simulateur**

Lancer l'app, onglet Carte, carte « VI ». L'icône crayon apparaît. L'armer, appui long sur la carte → la grille s'ouvre → choisir « Collectible » → un pin pointillé apparaît et le bandeau affiche « 1 brouillons ». Basculer sur la carte « V » : l'éditeur se désarme et le crayon disparaît.

- [ ] **Step 8 : Commit**

```bash
git add NeonCompass/Features/Map NeonCompass/Core/Map NeonCompass/Features/Community
git commit -m "feat(editor): brancher l'éditeur sur la carte — armement, capture, déplacement, adoption"
```

---

### Task 6 : `draft-to-poi.mjs` — la transformation, en pur

**Files:**
- Create: `tools/content-cli/draft-to-poi.mjs`
- Test: `tools/content-cli/draft-to-poi.test.mjs`

**Interfaces:**
- Consumes: `identityKey`, `mintId` de `tools/basemap/gtav-poi-ids.mjs`.
- Produces: `materialize(drafts, existing, { capturedOn })` → `{ writes, deletes, applied, skipped, conflicts }`, consommé par Task 7.

- [ ] **Step 1 : Écrire le test qui échoue**

`tools/content-cli/draft-to-poi.test.mjs` :

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { materialize, EDITOR_SOURCE } from './draft-to-poi.mjs';

const CAPTURED_ON = '2026-11-20';

function createDraft(overrides = {}) {
  return {
    id: 'uuid-1',
    kind: 'create',
    category: 'collectible',
    position: { x: 0.25, y: 0.5 },
    title: null,
    targetPOIID: null,
    sourceContributionID: null,
    ...overrides,
  };
}

test('un create frappe un id stable et écrit un fichier draft', () => {
  const result = materialize([createDraft()], [], { capturedOn: CAPTURED_ON });

  assert.equal(result.writes.length, 1);
  assert.equal(result.conflicts.length, 0);
  assert.deepEqual(result.applied, ['uuid-1']);

  const { data } = result.writes[0];
  assert.match(data.id, /^poi_leonida_collectible_[0-9a-f]{8}$/);
  assert.equal(data.status, 'draft');
  assert.deepEqual(data.position, { x: 0.25, y: 0.5 });
  assert.equal(data.processedFrom, `${EDITOR_SOURCE}:collectible:uuid-1`);
  assert.ok(data.sources.length >= 1);
  assert.ok(data.title.en.length > 0);
});

test('le même brouillon rejoué ne réécrit rien mais reste appliqué', () => {
  const first = materialize([createDraft()], [], { capturedOn: CAPTURED_ON });
  const existing = [{ path: 'content/poi/x.json', data: first.writes[0].data }];

  const second = materialize([createDraft()], existing, { capturedOn: CAPTURED_ON });

  assert.equal(second.writes.length, 0);
  assert.deepEqual(second.applied, ['uuid-1']);
});

test('un titre capturé remplace le titre généré', () => {
  const result = materialize([createDraft({ title: 'Lettre sur le toit' })], [], { capturedOn: CAPTURED_ON });
  assert.equal(result.writes[0].data.title.en, 'Lettre sur le toit');
});

test('une adoption cite la contribution d’origine dans sources', () => {
  const result = materialize(
    [createDraft({ sourceContributionID: 'c42' })],
    [],
    { capturedOn: CAPTURED_ON }
  );
  assert.ok(result.writes[0].data.sources.some((s) => s.includes('c42')));
});

test('un move réécrit la position du POI visé', () => {
  const existing = [{
    path: 'content/poi/poi_a.json',
    data: { id: 'poi_a', category: 'landmark', position: { x: 0.1, y: 0.1 }, title: { en: 'A' }, status: 'draft', sources: ['s'] },
  }];

  const result = materialize(
    [{ id: 'uuid-2', kind: 'move', targetPOIID: 'poi_a', position: { x: 0.8, y: 0.9 } }],
    existing,
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.writes.length, 1);
  assert.equal(result.writes[0].path, 'content/poi/poi_a.json');
  assert.deepEqual(result.writes[0].data.position, { x: 0.8, y: 0.9 });
});

test('un move vers un POI absent est signalé, pas appliqué à moitié', () => {
  const result = materialize(
    [{ id: 'uuid-3', kind: 'move', targetPOIID: 'poi_absent', position: { x: 0.5, y: 0.5 } }],
    [],
    { capturedOn: CAPTURED_ON }
  );

  assert.equal(result.writes.length, 0);
  assert.equal(result.skipped.length, 1);
  assert.deepEqual(result.applied, ['uuid-3']);
});

test('supprimer un POI publié écrit une pierre tombale, jamais une suppression', () => {
  const existing = [{
    path: 'content/poi/poi_b.json',
    data: { id: 'poi_b', category: 'landmark', position: { x: 0.1, y: 0.1 }, title: { en: 'B' }, status: 'published', sources: ['s'] },
  }];

  const result = materialize([{ id: 'uuid-4', kind: 'delete', targetPOIID: 'poi_b' }], existing, { capturedOn: CAPTURED_ON });

  assert.equal(result.deletes.length, 0);
  assert.equal(result.writes.length, 1);
  assert.equal(result.writes[0].data.deleted, true);
});

test('supprimer un POI jamais publié supprime le fichier', () => {
  const existing = [{
    path: 'content/poi/poi_c.json',
    data: { id: 'poi_c', category: 'landmark', position: { x: 0.1, y: 0.1 }, title: { en: 'C' }, status: 'draft', sources: ['s'] },
  }];

  const result = materialize([{ id: 'uuid-5', kind: 'delete', targetPOIID: 'poi_c' }], existing, { capturedOn: CAPTURED_ON });

  assert.deepEqual(result.deletes, ['content/poi/poi_c.json']);
  assert.equal(result.writes.length, 0);
});

test('un id frappé qui collisionne avec un autre processedFrom bloque tout', () => {
  const minted = materialize([createDraft()], [], { capturedOn: CAPTURED_ON }).writes[0].data;
  const existing = [{
    path: 'content/poi/collision.json',
    data: { ...minted, processedFrom: 'autre:source:autre-uuid' },
  }];

  const result = materialize([createDraft()], existing, { capturedOn: CAPTURED_ON });

  assert.equal(result.conflicts.length, 1);
  assert.equal(result.writes.length, 0);
  assert.equal(result.applied.length, 0);
});
```

- [ ] **Step 2 : Lancer le test, vérifier qu'il échoue**

Run: `cd tools/content-cli && node --test draft-to-poi.test.mjs`
Expected: FAIL — `Cannot find module './draft-to-poi.mjs'`.

- [ ] **Step 3 : Écrire `draft-to-poi.mjs`**

```js
// Transformation pure « brouillon d'éditeur → fichier content/poi ». Aucune I/O,
// aucun Firestore : tout ce qui décide vit ici, et `cli.js` ne fait qu'écrire ce
// qu'on lui rend. C'est ce qui rend cette pièce testable sans émulateur.

import { identityKey, mintId } from '../basemap/gtav-poi-ids.mjs';

/// Source d'identité des entrées nées de l'éditeur — la partie stable de la clé
/// écrite dans `processedFrom`.
export const EDITOR_SOURCE = 'editor';

/// L'éditeur ne pose que sur la carte du jeu à venir (spec D2).
const GAME = 'leonida';

const CATEGORY_LABELS = {
  landmark: 'Lieu',
  collectible: 'Collectible',
  activity: 'Activité',
  safehouse: 'Planque',
  vehicle: 'Véhicule',
  event: 'Événement',
};

function generatedTitle(category, capturedOn) {
  return `${CATEGORY_LABELS[category] ?? category} sans titre — ${capturedOn}`;
}

/**
 * @param drafts   brouillons non appliqués, tels que lus dans `editor_drafts`
 * @param existing [{ path, data }] — les fichiers actuels de content/poi
 * @param capturedOn date ISO courte, injectée pour que la fonction reste pure
 * @returns { writes, deletes, applied, skipped, conflicts }
 *   writes    [{ path, data }] à écrire (création ou réécriture)
 *   deletes   chemins à supprimer
 *   applied   ids de brouillons à marquer appliqués
 *   skipped   [{ id, reason }] — brouillons sans effet, marqués appliqués quand même
 *   conflicts [{ id, reason }] — si non vide, l'appelant n'écrit RIEN
 */
export function materialize(drafts, existing, { capturedOn }) {
  const byID = new Map(existing.map((entry) => [entry.data.id, entry]));
  const byProcessedFrom = new Map(
    existing.filter((entry) => entry.data.processedFrom).map((entry) => [entry.data.processedFrom, entry])
  );

  const writes = [];
  const deletes = [];
  const applied = [];
  const skipped = [];
  const conflicts = [];

  for (const draft of drafts) {
    if (draft.kind === 'create') {
      const category = draft.category;
      const key = identityKey(EDITOR_SOURCE, category, draft.id);

      // Déjà matérialisé lors d'un run précédent : on se réapparie, on n'écrit
      // pas une seconde entrée. C'est toute l'idempotence, et elle vient de la
      // clé, pas d'un drapeau.
      if (byProcessedFrom.has(key)) {
        applied.push(draft.id);
        continue;
      }

      const id = mintId(GAME, category, key);
      const collision = byID.get(id);
      if (collision) {
        conflicts.push({ id: draft.id, reason: `l'id frappé ${id} existe déjà avec un autre processedFrom` });
        continue;
      }

      const sources = ['observation directe en jeu, ' + capturedOn];
      if (draft.sourceContributionID) {
        sources.push(`contribution communautaire ${draft.sourceContributionID}`);
      }

      writes.push({
        path: `content/poi/${id}.json`,
        data: {
          id,
          category,
          position: draft.position,
          title: { en: draft.title || generatedTitle(category, capturedOn) },
          status: 'draft',
          sources,
          processedFrom: key,
        },
      });
      applied.push(draft.id);
      continue;
    }

    const target = byID.get(draft.targetPOIID);
    if (!target) {
      // Le POI a disparu du dépôt depuis la capture. Rien à faire, mais le
      // brouillon est classé : le laisser en attente le ferait resurgir à chaque
      // run.
      skipped.push({ id: draft.id, reason: `POI introuvable : ${draft.targetPOIID}` });
      applied.push(draft.id);
      continue;
    }

    if (draft.kind === 'move') {
      writes.push({ path: target.path, data: { ...target.data, position: draft.position } });
      applied.push(draft.id);
      continue;
    }

    if (draft.kind === 'delete') {
      if (target.data.status === 'published') {
        // Pierre tombale : le socle embarqué ne se décompile pas du binaire,
        // supprimer le fichier laisserait l'entrée vivante chez tous les clients.
        writes.push({ path: target.path, data: { ...target.data, deleted: true } });
      } else {
        deletes.push(target.path);
      }
      applied.push(draft.id);
      continue;
    }

    conflicts.push({ id: draft.id, reason: `kind inconnu : ${draft.kind}` });
  }

  // Un conflit invalide le lot entier : appliquer la moitié d'un run laisserait
  // le dépôt dans un état que personne ne peut raisonner.
  if (conflicts.length) {
    return { writes: [], deletes: [], applied: [], skipped: [], conflicts };
  }

  return { writes, deletes, applied, skipped, conflicts };
}
```

- [ ] **Step 4 : Lancer le test, vérifier qu'il passe**

Run: `cd tools/content-cli && node --test draft-to-poi.test.mjs`
Expected: PASS, 9 tests.

- [ ] **Step 5 : Commit**

```bash
git add tools/content-cli/draft-to-poi.mjs tools/content-cli/draft-to-poi.test.mjs
git commit -m "feat(tools): transformation pure brouillon d'éditeur → fichier POI"
```

---

### Task 7 : La commande `pull-drafts`

**Files:**
- Modify: `tools/content-cli/firestore-client.js`
- Modify: `tools/content-cli/cli.js`
- Modify: `tools/content-cli/ui/actions.mjs`

**Interfaces:**
- Consumes: `materialize` (Task 6).
- Produces: la commande `node cli.js pull-drafts` et l'action console `pull-drafts`.

- [ ] **Step 1 : Lire et marquer les brouillons**

Dans `firestore-client.js`, à la suite des fonctions de modération :

```js
/// Brouillons du mode éditeur pas encore matérialisés. `appliedAt` absent plutôt
/// qu'un booléen : la date sert aussi de trace de quand le dépôt les a absorbés.
export async function listEditorDrafts() {
  const db = app().firestore();
  const snapshot = await db.collection('editor_drafts').get();
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((draft) => !draft.appliedAt)
    .sort((a, b) => (a.capturedAt?.toMillis?.() ?? 0) - (b.capturedAt?.toMillis?.() ?? 0));
}

export async function markEditorDraftsApplied(ids) {
  const db = app().firestore();
  const batch = db.batch();
  ids.forEach((id) => batch.update(db.collection('editor_drafts').doc(id), { appliedAt: new Date() }));
  await batch.commit();
}
```

- [ ] **Step 2 : Ajouter la commande**

Dans `cli.js`, ajouter au bloc de commentaire d'en-tête :

```
//   pull-drafts            matérialise les brouillons du mode éditeur en fichiers
//                          content/poi/*.json ; nécessite FIREBASE_SERVICE_ACCOUNT_PATH.
```

et le `case`, à côté de `moderate:list` :

```js
  case 'pull-drafts':
    try {
      const { listEditorDrafts, markEditorDraftsApplied } = await import('./firestore-client.js');
      const { materialize } = await import('./draft-to-poi.mjs');

      const drafts = await listEditorDrafts();
      if (!drafts.length) {
        console.log('pull-drafts: aucun brouillon en attente');
        break;
      }

      const dir = join(CONTENT, 'poi');
      const existing = readdirSync(dir)
        .filter((name) => name.endsWith('.json'))
        .map((name) => ({
          path: join('content', 'poi', name),
          data: JSON.parse(readFileSync(join(dir, name), 'utf8')),
        }));

      const capturedOn = new Date().toISOString().slice(0, 10);
      const result = materialize(drafts, existing, { capturedOn });

      if (result.conflicts.length) {
        result.conflicts.forEach((c) => console.error(`  conflit ${c.id}: ${c.reason}`));
        console.error('pull-drafts: rien appliqué — résoudre les conflits d’abord');
        ok = false;
        break;
      }

      result.writes.forEach(({ path, data }) => {
        writeFileSync(join(ROOT, path), JSON.stringify(data, null, 2) + '\n');
        console.log(`  écrit  ${path}`);
      });
      result.deletes.forEach((path) => {
        rmSync(join(ROOT, path));
        console.log(`  retiré ${path}`);
      });
      result.skipped.forEach((s) => console.log(`  ignoré ${s.id}: ${s.reason}`));

      await markEditorDraftsApplied(result.applied);
      console.log(`pull-drafts: ${result.applied.length} brouillons appliqués`);
      ok = true;
    } catch (err) {
      console.error(err.message);
      ok = false;
    }
    break;
```

Ajouter `rmSync` à l'import de `node:fs` en tête de fichier, et `pull-drafts` à la ligne d'usage finale.

- [ ] **Step 3 : Exposer le bouton dans la console**

Dans `ui/actions.mjs`, section « Écritures locales » :

```js
  'pull-drafts': {
    label: 'Récupérer les brouillons de l’éditeur',
    group: 'local',
    hint: 'Matérialise ce qui a été posé au doigt en fichiers content/poi',
    argv: [CLI, 'pull-drafts'],
    writesRepo: true,
    needsCredentials: true,
  },
```

- [ ] **Step 4 : Vérifier que la liste blanche reste cohérente**

Run: `cd tools/content-cli && node --test ui/actions.test.mjs`
Expected: PASS, les 9 tests existants.

- [ ] **Step 5 : Vérifier la commande à vide**

Run: `cd tools/content-cli && node cli.js pull-drafts`
Expected: `pull-drafts: aucun brouillon en attente` (credentials présents, collection vide).

- [ ] **Step 6 : Commit**

```bash
git add tools/content-cli
git commit -m "feat(tools): commande pull-drafts et son bouton dans la console"
```

---

### Task 8 : Garde-fou de soumission et documentation

**Files:**
- Create: `Scripts/check-release-binary.sh`
- Create: `docs/ops/2026-07-27-editeur-interne.md`

- [ ] **Step 1 : Écrire la vérification**

```bash
#!/usr/bin/env bash
# Vérifie qu'aucune trace du mode éditeur n'a fui dans un binaire Release.
# Une garantie qu'on ne vérifie pas n'en est pas une : #if DEBUG protège, ce
# script le prouve. À lancer avant toute soumission App Store.
#
# Usage : Scripts/check-release-binary.sh [chemin/vers/NeonCompass.app]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
if [ -z "${APP}" ]; then
  echo "usage: Scripts/check-release-binary.sh <chemin/vers/NeonCompass.app>" >&2
  exit 2
fi

BINARY="${APP}/NeonCompass"
if [ ! -f "${BINARY}" ]; then
  echo "✗ binaire introuvable : ${BINARY}" >&2
  exit 2
fi

if strings "${BINARY}" | grep -q "NCEditorArmedMarker"; then
  echo "✗ le marqueur du mode éditeur est présent dans le binaire Release."
  echo "  L'éditeur a fui hors de #if DEBUG — NE PAS SOUMETTRE."
  exit 1
fi

echo "✓ aucun marqueur du mode éditeur dans ${BINARY}"
```

Puis `chmod +x Scripts/check-release-binary.sh`.

- [ ] **Step 2 : Écrire la note d'exploitation**

`docs/ops/2026-07-27-editeur-interne.md` — couvrir : relever son UID au premier armement (le bandeau l'affiche), le reporter dans `firestore.rules`, `node cli.js rules-diff` puis `deploy-rules`, la boucle de travail (capture en jeu → `pull-drafts` → compléter les textes → `release`), et l'appel à `Scripts/check-release-binary.sh` dans la checklist de soumission.

- [ ] **Step 3 : Renseigner l'UID et déployer les règles**

Lancer l'app en debug, armer l'éditeur, recopier l'UID affiché dans `firestore.rules` à la place de `REMPLACER_PAR_UID_EDITEUR`.

Run: `cd tools/content-cli && node cli.js rules-diff`
Expected: le diff ne montre que l'ajout du bloc `editor_drafts`.

Run: `node cli.js deploy-rules`

- [ ] **Step 4 : Boucle complète de bout en bout**

Poser trois pins dans le simulateur, puis :

Run: `cd tools/content-cli && node cli.js pull-drafts`
Expected: trois fichiers écrits dans `content/poi/`, `git status` les montre.

Run: `node cli.js validate`
Expected: les trois nouveaux fichiers passent le schéma.

- [ ] **Step 5 : Commit**

```bash
git add Scripts/check-release-binary.sh docs/ops/2026-07-27-editeur-interne.md firestore.rules
git commit -m "chore(editor): garde-fou de soumission, note d'exploitation, UID de l'éditeur"
```

---

## Auto-revue

**Couverture de la spec** — D1 : Tasks 1-4 (`#if DEBUG`) + Task 8 (vérification du marqueur). D2 : Task 3 (`canArm`, `mapChanged`) + Task 6 (`GAME = 'leonida'`, écriture dans `content/poi/`). D3 : Task 2. D4 : Task 6 (`identityKey`/`mintId`/`processedFrom`). D5 : Tasks 4-5. D6 : Tasks 1, 3, 5. D7 : Task 6 (pierre tombale si `published`). D8 : Task 6 (titre généré, `status: draft`, `sources`).

**Cohérence des types** — `EditorDraft.targetPOIID` (Swift) sérialise en `targetPOIID` et c'est bien ce que `draft-to-poi.mjs` lit. `DraftPin` est défini en Task 3 et consommé en Task 5. `materialize` retourne les cinq mêmes clés partout.

**Pas de placeholder** — une seule valeur reste à remplir volontairement, `REMPLACER_PAR_UID_EDITEUR`, dont la Task 8 Step 3 est la procédure de remplacement. Elle échoue fermée : tant qu'elle est là, personne n'écrit.
