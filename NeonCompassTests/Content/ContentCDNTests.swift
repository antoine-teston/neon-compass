import Foundation
import Testing
@testable import NeonCompass

/// Le CDN se teste pour de vrai, sans serveur : `URLSession` sait lire une URL
/// `file://`, donc un répertoire temporaire qui porte exactement l'arborescence
/// produite par `content-cli build-cdn` exerce le vrai chemin de décodage —
/// décompression comprise.
private struct CDNFixture {
    let baseURL: URL

    /// - Parameter versions: version PAR collection, comme dans le manifeste.
    init(versions: [String: Int], chunks: [String: [String]]) throws {
        baseURL = URL.temporaryDirectory.appending(path: "cdn-\(UUID().uuidString)")
        let contentDir = baseURL.appending(path: "content")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        let entries = versions.map { collection, version in
            #""\#(collection)":{"version":\#(version),"chunks":\#(chunks[collection]?.count ?? 0),"count":1}"#
        }
        let manifest = #"{"version":999,"commit":"abc1234","collections":{\#(entries.joined(separator: ","))}}"#
        try manifest.write(to: contentDir.appending(path: "manifest.json"), atomically: true, encoding: .utf8)

        for (collection, version) in versions {
            let versionDir = contentDir.appending(path: "v\(version)/\(collection)")
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            for (index, chunk) in (chunks[collection] ?? []).enumerated() {
                // `.json.z`, compressé : exactement ce que `build-cdn` écrit.
                let compressed = try (Data(chunk.utf8) as NSData).compressed(using: .zlib) as Data
                try compressed.write(to: versionDir.appending(path: "\(index).json.z"))
            }
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

        // Effacer l'URL est le geste de repli d'urgence : il ne doit pas
        // demander de mise à jour de l'app.
        await cdn.configure(baseURL: nil)
        #expect(await cdn.isConfigured() == false)
    }

    @Test func decodesTheManifestAndItsBundles() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 231],
            chunks: ["poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a", "b"])]]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let manifest = try await cdn.manifest()
        #expect(manifest.collections["poi"]?.chunks == 1)
        #expect(manifest.collections["poi"]?.version == 231)

        let bundles: [ContentBundle<POI>] = try await cdn.bundles(for: "poi")
        #expect(bundles.flatMap(\.items).map(\.id) == ["a", "b"])
    }

    /// Chaque collection est allée chercher SA version, pas celle de la
    /// publication. C'est tout l'intérêt : une collection inchangée garde son
    /// chemin, donc son cache, donc ne repart pas sur le réseau.
    @Test func eachCollectionReadsItsOwnVersion() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 10, "cheats": 11],
            chunks: [
                "poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["p"])],
                "cheats": [CDNFixture.bundle(collection: "cheats", chunk: 0, poiIDs: ["c"])],
            ]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        #expect(try await cdn.version(for: "poi") == 10)
        #expect(try await cdn.version(for: "cheats") == 11)
        // Le manifeste porte 999 : personne ne doit s'en servir pour décider.
        #expect(try await cdn.manifest().version == 999)
    }

    @Test func anUnpublishedCollectionIsVersionZeroRatherThanAnError() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 1],
            chunks: ["poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"])]]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        #expect(try await cdn.version(for: "guides") == 0)
    }

    /// Un fragment illisible ne doit pas vider toute la collection — que
    /// l'illisibilité vienne du JSON ou de la décompression.
    @Test func aMalformedChunkDoesNotEmptyTheCollection() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 3],
            chunks: [
                "poi": [
                    CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"]),
                    "{ ceci n'est pas du JSON",
                ],
            ]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let bundles: [ContentBundle<POI>] = try await cdn.bundles(for: "poi")
        #expect(bundles.flatMap(\.items).map(\.id) == ["a"])
    }

    @Test func aChunkThatIsNotCompressedAtAllIsSkippedNotFatal() async throws {
        let fixture = try CDNFixture(versions: ["poi": 4], chunks: ["poi": []])
        defer { fixture.cleanUp() }

        // Un fragment écrit en clair là où le client attend du DEFLATE : le cas
        // d'une publication faite par un outil qui aurait oublié de compresser.
        let dir = fixture.baseURL.appending(path: "content/v4/poi")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"]).utf8)
            .write(to: dir.appending(path: "0.json.z"))
        // Le manifeste annonce 0 fragment ; on en force la lecture par une
        // fixture à un fragment.
        let manifest = #"{"version":999,"commit":"x","collections":{"poi":{"version":4,"chunks":1,"count":1}}}"#
        try manifest.write(to: fixture.baseURL.appending(path: "content/manifest.json"),
                           atomically: true, encoding: .utf8)

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let bundles: [ContentBundle<POI>] = try await cdn.bundles(for: "poi")
        #expect(bundles.isEmpty)
    }

    @Test func anUnknownCollectionYieldsNothingRatherThanFailing() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 1],
            chunks: ["poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"])]]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)

        let bundles: [ContentBundle<Cheat>] = try await cdn.bundles(for: "cheats")
        #expect(bundles.isEmpty)
    }
}

/// L'accord de compression vit des DEUX CÔTÉS d'une frontière réseau : Node
/// compresse à la publication, iOS décompresse à la lecture. Le tester avec une
/// fixture produite par Swift lui-même ne prouverait rien — les deux côtés
/// pourraient dériver ensemble.
///
/// Cette charge a donc été produite par `zlib.deflateRawSync(…, { level: 9 })`
/// sous Node 22, puis encodée en base64. Si un jour `.zlib` du framework
/// Compression cesse d'être du DEFLATE brut, ou si la publication passe au gzip
/// (qui ajoute un en-tête de 10 octets), ce test tombe — et c'est le seul
/// endroit où ça se verrait avant la mise en production.
struct DeflateInteropTests {
    private static let nodeProduced = """
    JY2xCgIxEER7v+KYOoqNzX2E2ItFSBZdLsmG3B54hPz7JVoNvBneVDgJgZyyJMzIwjBwny0tmK8G\
    rBRXzM8K9r1O4ukcracxskpvKXvHwSYfbVk6zbLy31Xx7YrLzWD/ZTNQ1kCjofH1KOI31inbMt27\
    GK292ukA
    """

    @Test func inflatesAPayloadProducedByNode() throws {
        let compressed = try #require(Data(base64Encoded: Self.nodeProduced))
        let inflated = try ContentCDN.inflate(compressed)
        let bundle = try JSONDecoder().decode(ContentBundle<POI>.self, from: inflated)

        #expect(bundle.collection == "poi")
        #expect(bundle.items.map(\.id) == ["node-made"])
    }

    @Test func compressionActuallyEarnsItsKeep() throws {
        // 120 octets compressés pour 145 en clair sur cette fixture minuscule ;
        // le rapport monte avec la taille. Le test garde surtout qu'on ne
        // publie pas par erreur un « compressé » plus gros que l'original.
        let compressed = try #require(Data(base64Encoded: Self.nodeProduced))
        let inflated = try ContentCDN.inflate(compressed)
        #expect(compressed.count < inflated.count)
    }
}

struct CDNContentRepositoryTests {
    @Test func readsTheCDNWhenConfigured() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 7],
            chunks: ["poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["from-cdn"])]]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        await cdn.configure(baseURL: fixture.baseURL)
        let repository = CDNContentRepository<POI>(collectionName: "poi", cdn: cdn)

        #expect(try await repository.fetchAll().map(\.id) == ["from-cdn"])
    }

    /// Sans CDN configuré, le dépôt LÈVE au lieu de rendre une collection vide.
    ///
    /// La nuance décide de ce que voit l'utilisateur : `ContentStore` écrit ce
    /// que le dépôt rend dans son cache. Rendre `[]` écraserait le contenu
    /// déjà en cache par du vide, sur une simple panne réseau au lancement.
    @Test func throwsRatherThanReturningNothingWhenNoBaseURLIsConfigured() async throws {
        let repository = CDNContentRepository<POI>(collectionName: "poi", cdn: ContentCDN())
        await #expect(throws: ContentCDNError.self) { try await repository.fetchAll() }
    }

    @Test func versionProviderReadsItsOwnCollection() async throws {
        let fixture = try CDNFixture(
            versions: ["poi": 42, "cheats": 8],
            chunks: [
                "poi": [CDNFixture.bundle(collection: "poi", chunk: 0, poiIDs: ["a"])],
                "cheats": [CDNFixture.bundle(collection: "cheats", chunk: 0, poiIDs: ["c"])],
            ]
        )
        defer { fixture.cleanUp() }

        let cdn = ContentCDN()
        let poiVersion = CDNContentVersionProvider(collectionName: "poi", cdn: cdn)

        // Non configuré : zéro, donc ContentStore ne télécharge rien et garde
        // son cache.
        #expect(try await poiVersion.currentVersion() == 0)

        await cdn.configure(baseURL: fixture.baseURL)
        #expect(try await poiVersion.currentVersion() == 42)
        #expect(try await CDNContentVersionProvider(collectionName: "cheats", cdn: cdn).currentVersion() == 8)
    }
}
