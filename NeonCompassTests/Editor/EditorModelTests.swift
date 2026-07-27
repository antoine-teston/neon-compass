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

/// Identifiants déterministes : les tests ne dépendent ni de `UUID()` ni de
/// l'horloge.
private final class IDCounter: @unchecked Sendable {
    private var value = 0
    func next() -> String {
        value += 1
        return "u\(value)"
    }
}

/// Hors du type isolé MainActor : une closure `@Sendable` ne peut pas capturer
/// une propriété statique isolée.
private let fixedDate = Date(timeIntervalSince1970: 1_763_000_000)

@MainActor
struct EditorModelTests {
    /// `isBackendAvailable` forcé à vrai : les tests tournent sans Firebase
    /// configuré, et l'armement en dépend.
    private func makeModel(store: SpyDraftStore, backendAvailable: Bool = true) -> EditorModel {
        let counter = IDCounter()
        return EditorModel(
            store: store,
            makeID: { counter.next() },
            now: { fixedDate },
            isBackendAvailable: { backendAvailable }
        )
    }

    private func spot(id: String = "c7", category: POICategory = .activity, title: String = "Rampe derrière l'entrepôt") -> Contribution {
        Contribution(
            id: id,
            authorUid: "uid",
            authorHandle: "h",
            category: category,
            title: title,
            languageCode: "fr",
            position: NormalizedPoint(x: 0.2, y: 0.8),
            status: .approved,
            upvotes: 4,
            downvotes: 1
        )
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

    /// Sans Firebase configuré, capturer enverrait les brouillons dans le vide —
    /// et le premier appel au SDK planterait d'une erreur fatale non rattrapable.
    /// Le bouton ne doit donc même pas apparaître.
    @Test func refusesToArmWithoutABackend() {
        let model = makeModel(store: SpyDraftStore(), backendAvailable: false)
        #expect(!model.canArm(on: .leonida))

        model.setArmed(true, on: .leonida)
        #expect(!model.isArmed)
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

    @Test func captureSavesADraftAndShowsItsPin() {
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

    /// Un appui long alors qu'un déplacement est armé pose la destination — il ne
    /// crée surtout pas un nouveau POI.
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

    @Test func longPressIsIgnoredWhenNotArmed() {
        let model = makeModel(store: SpyDraftStore())
        #expect(model.handleLongPress(at: NormalizedPoint(x: 0.3, y: 0.3)) == .ignored)
        #expect(model.pendingCapture == nil)
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

        model.adopt(spot())

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

    /// Désarmer doit aussi annuler ce qui était en cours : rester en attente
    /// d'une catégorie alors que l'éditeur est éteint est un état incohérent.
    @Test func disarmingCancelsPendingState() {
        let model = makeModel(store: SpyDraftStore())
        model.setArmed(true, on: .leonida)
        _ = model.handleLongPress(at: NormalizedPoint(x: 0.1, y: 0.1))
        model.beginMove(poiID: "poi_a")

        model.setArmed(false, on: .leonida)

        #expect(model.pendingCapture == nil)
        #expect(model.pendingMovePOIID == nil)
    }
}
#endif
