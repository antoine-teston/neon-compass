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

    func save(_ draft: EditorDraft) throws {
        if let errorToThrow { throw errorToThrow }
        saved.append(draft.id)
    }

    func waitForDelivery() async throws { deliveryWaits += 1 }
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
    @Test func usesFirestoreWhenAnAccountIsAvailable() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        try router.save(draft("u1"))

        #expect(remote.saved == ["u1"])
        #expect(local.saved.isEmpty)
    }

    /// Le cas qui compte aujourd'hui : sans compte — donc sans adhésion au
    /// programme développeur Apple — la capture doit quand même atterrir.
    @Test func fallsBackToTheFileWithoutAnAccount() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { false })

        try router.save(draft("u1"))

        #expect(local.saved == ["u1"])
        #expect(remote.saved.isEmpty)
    }

    /// Un refus distant ne doit jamais perdre une capture : quelqu'un qui a les
    /// mains sur une manette ne peut pas la ressaisir.
    @Test func aRemoteRefusalStillLandsInTheFile() throws {
        let remote = RecordingStore(), local = RecordingStore()
        remote.errorToThrow = Refused()
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { true })

        try router.save(draft("u1"))

        #expect(local.saved == ["u1"])
    }

    /// La décision se prend à chaque écriture : une connexion en cours de
    /// session doit être prise en compte sans reconstruire l'éditeur.
    @Test func theChoiceIsMadePerSaveNotAtConstruction() throws {
        let remote = RecordingStore(), local = RecordingStore()
        let signedIn = MutableFlag(false)
        let router = EditorDraftRouter(remote: remote, local: local, isRemoteUsable: { signedIn.value })

        try router.save(draft("u1"))
        signedIn.value = true
        try router.save(draft("u2"))

        #expect(local.saved == ["u1"])
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
