#if DEBUG
import Foundation
import Testing
@testable import NeonCompass

private let fixedDate = Date(timeIntervalSince1970: 1_763_000_000)

private func draft(_ id: String, _ category: POICategory = .collectible) -> EditorDraft {
    EditorDraft.create(id: id, category: category, at: NormalizedPoint(x: 0.4, y: 0.6), capturedAt: fixedDate)
}

private final class RecordingStore: EditorDraftStore, @unchecked Sendable {
    private(set) var saved: [String] = []
    private(set) var deliveryWaits = 0
    var errorToThrow: Error?
    /// Distinct de `errorToThrow`, et c'est tout le sujet : le magasin distant
    /// réel ACCEPTE toujours puis échoue à la livraison. Un unique interrupteur
    /// d'erreur ne saurait pas jouer ce cas — celui qui a perdu les captures.
    var deliveryError: Error?

    func save(_ draft: EditorDraft) throws {
        if let errorToThrow { throw errorToThrow }
        saved.append(draft.id)
    }

    func waitForDelivery() async throws {
        deliveryWaits += 1
        if let deliveryError { throw deliveryError }
    }
}

private struct Refused: Error {}

struct FileEditorDraftStoreTests {
    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesAndReReadsADraft() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileEditorDraftStore(directory: directory)

        try store.save(draft("u1"))

        let reloaded = FileEditorDraftStore.load(from: store.fileURL)
        #expect(reloaded.map(\.id) == ["u1"])
        #expect(reloaded[0].category == .collectible)
        #expect(reloaded[0].position == NormalizedPoint(x: 0.4, y: 0.6))
    }

    @Test func accumulatesAcrossSavesAndSurvivesANewInstance() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileEditorDraftStore(directory: directory).save(draft("u1"))
        try FileEditorDraftStore(directory: directory).save(draft("u2", .vehicle))

        let store = FileEditorDraftStore(directory: directory)
        #expect(FileEditorDraftStore.load(from: store.fileURL).map(\.id) == ["u1", "u2"])
    }

    /// Réenregistrer le même identifiant remplace au lieu de dupliquer : inutile
    /// de donner des doublons à trier à `pull-drafts`.
    @Test func rewritingTheSameIDReplacesIt() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileEditorDraftStore(directory: directory)

        try store.save(draft("u1", .collectible))
        try store.save(draft("u1", .safehouse))

        let reloaded = FileEditorDraftStore.load(from: store.fileURL)
        #expect(reloaded.count == 1)
        #expect(reloaded[0].category == .safehouse)
    }

    @Test func anAbsentFileReadsAsEmptyRatherThanFailing() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FileEditorDraftStore(directory: directory).fileURL.lastPathComponent == "editor-drafts.json")
        #expect(FileEditorDraftStore.load(from: directory.appending(path: "rien.json")).isEmpty)
    }
}

struct EditorDraftRouterTests {
    /// **Le fichier est écrit TOUJOURS**, compte ou pas.
    ///
    /// Le contrat d'avant en faisait une alternative — distant OU fichier — et
    /// c'est ce qui a perdu cinq captures le 2026-08-05 : le magasin distant
    /// réel est un acteur dont `save` empile en mémoire et rend la main sans
    /// jamais lever. Le `catch` du routeur ne pouvait donc pas se déclencher, et
    /// la file, refusée par la RLS, mourait à la fermeture de l'app.
    ///
    /// Écrire des deux côtés est sans danger et le routeur le disait déjà :
    /// `pull-drafts` se réapparie par `processedFrom`, donc un brouillon passé
    /// par les deux chemins ne produit pas deux entrées.
    @Test func theFileIsAlwaysWrittenEvenWithAnAccount() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        try router.save(draft("u1"))

        #expect(local.saved == ["u1"], "la durabilité tient au fichier, jamais à la file distante")
        #expect(remote.saved == ["u1"])
    }

    /// Le cas de la régression, isolé : un magasin distant qui ACCEPTE sans
    /// jamais livrer — la forme exacte de `SupabaseEditorDraftStore`, dont le
    /// `save` est `nonisolated` et se contente d'empiler.
    @Test func aRemoteThatAcceptsButNeverDeliversDoesNotSwallowTheCapture() async throws {
        let remote = RecordingStore(), local = RecordingStore()
        remote.deliveryError = Refused()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        try router.save(draft("u1"))
        // La livraison échoue, comme sous une RLS qui refuse.
        await #expect(throws: Refused.self) { try await router.waitForDelivery() }

        #expect(local.saved == ["u1"], "la capture doit survivre à l'échec de livraison")
    }

    /// Sans compte — donc sans adhésion au programme développeur Apple — rien ne
    /// part au distant, et la capture atterrit quand même.
    @Test func nothingGoesRemoteWithoutAnAccount() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { false })

        try router.save(draft("u1"))

        #expect(local.saved == ["u1"])
        #expect(remote.saved.isEmpty)
    }

    /// Un refus distant ne doit jamais perdre une capture : quelqu'un qui a les
    /// mains sur une manette ne peut pas la ressaisir.
    @Test func aRemoteRefusalDoesNotFailTheCapture() throws {
        let remote = RecordingStore(), local = RecordingStore()
        remote.errorToThrow = Refused()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        try router.save(draft("u1"))

        #expect(local.saved == ["u1"])
    }

    /// Le fichier, lui, n'a pas de repli : s'il tombe, la capture est vraiment
    /// perdue et l'éditeur doit le savoir plutôt que de l'annoncer enregistrée.
    @Test func aFileFailureIsFatalToTheCapture() throws {
        let remote = RecordingStore(), local = RecordingStore()
        local.errorToThrow = Refused()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        #expect(throws: Refused.self) { try router.save(draft("u1")) }
    }

    /// La décision se prend à chaque écriture : une connexion en cours de
    /// session doit être prise en compte sans reconstruire l'éditeur. Elle ne
    /// porte plus que sur le DISTANT — le fichier reçoit les deux.
    @Test func theRemoteChoiceIsMadePerSaveNotAtConstruction() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let signedIn = MutableFlag(false)
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { signedIn.value })

        try router.save(draft("u1"))
        signedIn.value = true
        try router.save(draft("u2"))

        #expect(local.saved == ["u1", "u2"])
        #expect(remote.saved == ["u2"])
    }

    @Test func doesNotWaitForDeliveryWhenWritingToTheFile() async throws {
        let remote = RecordingStore(), local = RecordingStore()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { false })

        try await router.waitForDelivery()

        #expect(remote.deliveryWaits == 0)
    }
}

private final class MutableFlag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
#endif
