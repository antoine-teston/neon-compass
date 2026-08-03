import Foundation
import SwiftData
import Testing
@testable import NeonCompass

/// Espion de transport : retient ce qui monte, rend ce qu'on lui a posé.
private actor FakePersonalPinSync: PersonalPinSyncing {
    private var uploaded: [PersonalPinSyncItem] = []
    private let remote: [PersonalPinSyncItem]

    init(remote: [PersonalPinSyncItem] = []) { self.remote = remote }

    func upload(_ item: PersonalPinSyncItem) async { uploaded.append(item) }
    func fetchAll(uid: String) async -> [PersonalPinSyncItem] { remote }
    func uploadedItems() -> [PersonalPinSyncItem] { uploaded }
}

@MainActor
struct PersonalPinReconciliationTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func item(
        id: UUID = UUID(), title: String = "Distante", isDone: Bool = false,
        updatedAt: Date, deletedAt: Date? = nil
    ) -> PersonalPinSyncItem {
        PersonalPinSyncItem(
            id: id, game: Game.reference.rawValue, x: 0.4, y: 0.4,
            title: title, note: "", icon: PersonalPinIcon.marker.rawValue,
            isDone: isDone, createdAt: updatedAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }

    /// Le cas qui vend Pro : une épingle posée sur l'iPad apparaît sur l'iPhone.
    @Test func anUnknownRemotePinIsAdopted() {
        let store = PersonalPinStore(modelContext: makeContext())
        store.reconcile(with: [item(title: "Posée sur l'iPad", updatedAt: .now)])
        #expect(store.pins.count == 1)
        #expect(store.pins[0].title == "Posée sur l'iPad")
    }

    /// Dernière-écriture-gagne, sens distant.
    @Test func aNewerRemoteEditWins() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = Date.now.addingTimeInterval(-120)
        store.reconcile(with: [item(id: pin.id, title: "Renommée ailleurs", updatedAt: .now)])
        #expect(store.pins.count == 1)
        #expect(store.pins[0].title == "Renommée ailleurs")
    }

    /// Dernière-écriture-gagne, sens local. Sans cette borne, un appareil resté
    /// hors ligne longtemps écraserait le travail récent de l'autre.
    @Test func anOlderRemoteEditLoses() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.update(pin, title: "Écrite ici", note: "")
        store.reconcile(with: [item(id: pin.id, title: "Vieille version",
                                    updatedAt: Date.now.addingTimeInterval(-3600))])
        #expect(store.pins[0].title == "Écrite ici")
    }

    /// La tombe voyage : effacer sur l'iPad efface sur l'iPhone. C'est tout
    /// l'intérêt de `deletedAt`.
    @Test func aRemoteTombstoneHidesTheLocalPin() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = Date.now.addingTimeInterval(-120)
        let now = Date.now
        store.reconcile(with: [item(id: pin.id, updatedAt: now, deletedAt: now)])
        #expect(store.pins.isEmpty)
    }

    /// Mais une tombe PLUS ANCIENNE que l'édition locale ne l'emporte pas :
    /// renommer ici après avoir supprimé là-bas doit garder l'épingle.
    @Test func anOlderRemoteTombstoneLoses() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.update(pin, title: "Ressaisie ici", note: "")
        let old = Date.now.addingTimeInterval(-3600)
        store.reconcile(with: [item(id: pin.id, updatedAt: old, deletedAt: old)])
        #expect(store.pins.count == 1, "une tombe périmée ne doit pas effacer une édition récente")
    }

    /// Une tombe distante qu'on n'a jamais connue ne crée RIEN. Adopter la ligne
    /// remplirait le disque de fantômes, un par épingle jamais vue.
    @Test func anUnknownRemoteTombstoneCreatesNothing() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let now = Date.now
        store.reconcile(with: [item(updatedAt: now, deletedAt: now)])
        #expect(store.pins.isEmpty)
        let all = (try? context.fetch(FetchDescriptor<PersonalPin>())) ?? []
        #expect(all.isEmpty, "aucune ligne ne doit être créée pour une tombe inconnue")
    }

    /// Réconcilier fait avancer la génération : la carte doit redessiner ce qui
    /// vient d'arriver, sinon les épingles de l'autre appareil restent
    /// invisibles jusqu'au prochain changement.
    @Test func reconcilingAdvancesTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let before = store.generation
        store.reconcile(with: [item(updatedAt: .now)])
        #expect(store.generation != before)
    }

    /// Ce que le distant ignore doit monter : une épingle posée hors ligne n'a
    /// jamais été téléversée, et rien d'autre ne la pousserait faute d'un
    /// drapeau « à envoyer » sur le modèle.
    @Test func localOnlyPinsAreUploaded() async {
        let store = PersonalPinStore(modelContext: makeContext())
        let sync = FakePersonalPinSync()
        store.attachSyncIfNeeded(sync)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.reconcile(with: [])
        try? await Task.sleep(for: .milliseconds(300))
        let uploaded = await sync.uploadedItems()
        #expect(uploaded.contains { $0.id == pin.id })
    }

    /// Et ce que le distant connaît déjà ne remonte PAS : renvoyer tout le
    /// carnet à chaque lancement gaspillerait le réseau de l'utilisateur pour
    /// réécrire ce qui est identique.
    @Test func remotelyKnownPinsAreNotReUploaded() async {
        let store = PersonalPinStore(modelContext: makeContext())
        let sync = FakePersonalPinSync()
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        // Attachée APRÈS la création : rien n'a encore été téléversé.
        store.attachSyncIfNeeded(sync)
        store.reconcile(with: [item(id: pin.id, title: "Déjà là-haut", updatedAt: .now)])
        try? await Task.sleep(for: .milliseconds(300))
        let uploaded = await sync.uploadedItems()
        #expect(uploaded.isEmpty, "une épingle que le distant possède déjà ne doit pas remonter")
    }

    /// Chaque mutation monte. Sans ça la synchro ne serait qu'une lecture, et
    /// cocher une épingle ne se verrait jamais sur l'autre appareil.
    @Test func everyMutationIsUploaded() async {
        let store = PersonalPinStore(modelContext: makeContext())
        let sync = FakePersonalPinSync()
        store.attachSyncIfNeeded(sync)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.update(pin, title: "Nommée", note: "Annotée")
        store.setIcon(.vehicle, on: pin)
        store.toggleDone(pin)
        store.delete(pin)
        try? await Task.sleep(for: .milliseconds(400))
        let uploaded = await sync.uploadedItems()
        #expect(uploaded.count == 5, "création, titre, icône, coche et suppression — obtenu \(uploaded.count)")
        #expect(uploaded.last?.deletedAt != nil, "le dernier envoi doit porter la tombe")
    }

    /// La synchro ne s'attache qu'une fois : `MapScreen` la propose à chaque
    /// apparition pour rattraper la course du droit Pro, et ça ne doit pas
    /// remplacer celle qui travaille déjà.
    @Test func attachingIsIdempotent() {
        let store = PersonalPinStore(modelContext: makeContext())
        #expect(store.attachSyncIfNeeded(FakePersonalPinSync()))
        #expect(!store.attachSyncIfNeeded(FakePersonalPinSync()))
    }

    /// Sans synchro attachée — le cas du joueur gratuit — rien ne part, et rien
    /// ne casse. Le magasin ne connaît ni le droit Pro ni le compte.
    @Test func nothingIsUploadedWithoutASync() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false)!
        store.update(pin, title: "Locale", note: "")
        store.delete(pin)
        #expect(store.pins.isEmpty)
    }
}
