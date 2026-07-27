import Foundation
import Testing
@testable import NeonCompass

/// Le CDN se teste pour de vrai, sans serveur : `URLSession` sait lire une URL
/// `file://`, donc un répertoire temporaire qui porte exactement l'arborescence
/// produite par `content-cli build-cdn` exerce le vrai chemin de décodage.
private struct CDNFixture {
    let baseURL: URL

    init(version: Int, collection: String, chunks: [String]) throws {
        baseURL = URL.temporaryDirectory.appending(path: "cdn-\(UUID().uuidString)")
        let manifest = """
        {"version":\(version),"commit":"abc1234","collections":{"\(collection)":{"chunks":\(chunks.count),"count":1}}}
        """
        let contentDir = baseURL.appending(path: "content")
        let versionDir = contentDir.appending(path: "v\(version)/\(collection)")
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try manifest.write(to: contentDir.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        for (index, chunk) in chunks.enumerated() {
            try chunk.write(to: versionDir.appending(path: "\(index).json"), atomically: true, encoding: .utf8)
        }
    }

    static func bundle(collection: String, chunk: Int, poiIDs: [String]) -> String {
        let items = poiIDs.map { #"{"id":"\#($0)","category":"landmark","position":{"x":0.5,"y":0.5},"title":{"en":"\#($0)"}}"# }
        return #"{"collection":"\#(collection)","chunk":\#(chunk),"items":[\#(items.joined(separator: ","))]}"#
    }

    func cleanUp() { try? FileManager.default.removeItem(at: baseURL) }
}

struct ContentCDNTests {
    @Test func isNotConfiguredUntilGivenABaseURL() async {
        let cdn = ContentCDN()
        #expect(await cdn.isConfigured() == false)

        await cdn.configure(baseURL: URL(string: "https://example.invalid"))
        #expect(await cdn.isConfigured())

        // Effacer l'URL doit ramener au repli Firestore : c'est le geste de
        // repli d'urgence, il ne doit pas demander de mise à jour de l'app.
        await cdn.configure(baseURL: nil)
        #expect(await cdn.isConfigured() == false)
    }

    @Test func decodesTheManifestAndItsBundles() async throws {
        let fixture = try CDNFixture(
            version: 231,
            collection: "poi",
            chunks: [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a", "b"])]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let manifest = try await cdn.manifest()
        #expect(manifest.version == 231)
        #expect(manifest.collections["poi"]?.chunks == 1)

        let bundles: [ContentBundle<POI>] = try await cdn.bundles(for: "poi")
        #expect(bundles.flatMap(\.items).map(\.id) == ["a", "b"])
    }

    /// Même politique que `ChunkedContentRepository` : un fragment illisible ne
    /// doit pas vider toute la collection.
    @Test func aMalformedChunkDoesNotEmptyTheCollection() async throws {
        let fixture = try CDNFixture(
            version: 3,
            collection: "poi",
            chunks: [
                CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"]),
                "{ ceci n'est pas du JSON",
            ]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let bundles: [ContentBundle<POI>] = try await cdn.bundles(for: "poi")
        #expect(bundles.flatMap(\.items).map(\.id) == ["a"])
    }

    @Test func anUnknownCollectionYieldsNothingRatherThanFailing() async throws {
        let fixture = try CDNFixture(
            version: 1,
            collection: "poi",
            chunks: [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"])]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let bundles: [ContentBundle<Cheat>] = try await cdn.bundles(for: "cheats")
        #expect(bundles.isEmpty)
    }
}

struct CDNContentRepositoryTests {
    /// L'invariant qui rend la bascule sûre : tant qu'aucune URL n'est
    /// configurée, rien ne change — on lit Firestore exactement comme avant.
    @Test func fallsBackToFirestoreWhenNoBaseURLIsConfigured() async throws {
        let fallback = FakeContentRepository<POI>()
        fallback.itemsToReturn = [POI(id: "from-firestore", category: .landmark, position: nil,
                                      title: LocalizedText(en: "x", fr: nil, es: nil, it: nil, de: nil))]
        let repository = CDNContentRepository(collectionName: "poi", firestoreFallback: fallback, cdn: ContentCDN())

        let items = try await repository.fetchAll()

        #expect(items.map(\.id) == ["from-firestore"])
        #expect(fallback.fetchCallCount == 1)
    }

    @Test func readsTheCDNAndLeavesFirestoreAloneWhenConfigured() async throws {
        let fixture = try CDNFixture(
            version: 7,
            collection: "poi",
            chunks: [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["from-cdn"])]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)
        let fallback = FakeContentRepository<POI>()
        let repository = CDNContentRepository(collectionName: "poi", firestoreFallback: fallback, cdn: cdn)

        let items = try await repository.fetchAll()

        #expect(items.map(\.id) == ["from-cdn"])
        #expect(fallback.fetchCallCount == 0)
    }

    @Test func versionProviderFollowsTheSameRule() async throws {
        let fixture = try CDNFixture(
            version: 42,
            collection: "poi",
            chunks: [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"])]
        )
        defer { fixture.cleanUp() }

        let firestoreVersion = FakeContentVersionProvider()
        firestoreVersion.version = 3

        let cdn = ContentCDN()
        let provider = CDNContentVersionProvider(firestoreFallback: firestoreVersion, cdn: cdn)
        #expect(try await provider.currentVersion() == 3)

        await cdn.configure(baseURL: fixture.baseURL)
        #expect(try await provider.currentVersion() == 42)
    }
}
