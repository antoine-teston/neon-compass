#if DEBUG
import Foundation
import Observation

/// État du mode éditeur : ce qui est armé, ce qui a été capturé, ce qui attend
/// encore d'être envoyé.
///
/// Toute la règle de geste vit ici plutôt que dans la vue — `handleLongPress`
/// rend explicite ce qu'un appui long a déclenché, pour que `MapScreen` n'ait
/// aucune décision à reprendre.
@Observable
@MainActor
final class EditorModel {
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

    init(
        store: EditorDraftStore,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.makeID = makeID
        self.now = now
    }

    /// Une seule condition : la carte. L'éditeur ne s'arme que sur celle du jeu
    /// à venir — la carte de référence n'est là que pour donner du volume
    /// explorable avant la sortie, y poser du contenu éditorial n'aurait aucun
    /// sens et ses coordonnées ne sont pas comparables.
    ///
    /// Il y avait autrefois une seconde condition, la disponibilité du backend :
    /// sans compte, capturer aurait envoyé les brouillons dans le vide. Elle a
    /// disparu avec le repli fichier (`EditorDraftRouter`) — une capture atterrit
    /// désormais toujours quelque part, compte ou pas.
    func canArm(on game: MapGame) -> Bool { game == .leonida }

    func setArmed(_ armed: Bool, on game: MapGame) {
        isArmed = armed && canArm(on: game)
        if !isArmed { cancelPending() }
    }

    /// Désarme si la carte affichée ne peut pas recevoir d'ajouts. Sans ça, un
    /// appui long après bascule créerait un POI aux coordonnées d'une autre carte.
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
        record(EditorDraft.move(id: makeID(), poiID: poiID, to: position, capturedAt: now()), pin: nil)
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
    /// cas nominal en session de jeu — le compteur GARDE sa valeur : afficher
    /// zéro laisserait croire que tout est parti.
    func awaitDelivery() async {
        do {
            try await store.waitForDelivery()
            undeliveredCount = 0
        } catch {
            // Rien à faire : le bandeau continue d'annoncer ce qui reste à envoyer.
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
