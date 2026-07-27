import Foundation
import Testing
@testable import NeonCompass

struct ContentMergeTests {
    private func text(_ value: String) -> LocalizedText {
        LocalizedText(en: value, fr: nil, es: nil, it: nil, de: nil)
    }

    private func poi(
        _ id: String,
        title: String = "t",
        x: Double = 0,
        deleted: Bool? = nil
    ) -> POI {
        POI(id: id, category: .landmark, collection: "set", position: NormalizedPoint(x: x, y: 0),
            title: text(title), deleted: deleted)
    }

    @Test func returnsTheSeedWhenTheOverlayIsEmpty() {
        let seed = [poi("a"), poi("b")]
        #expect(ContentMerge.merge(seed: seed, overlay: []).map(\.id) == ["a", "b"])
    }

    @Test func returnsTheOverlayWhenThereIsNoSeed() {
        // Le cas des collections purement distantes : cheats, guides, actu.
        let overlay = [poi("a"), poi("b")]
        #expect(ContentMerge.merge(seed: [], overlay: overlay).map(\.id) == ["a", "b"])
    }

    @Test func overlayOverridesTheSeedOnMatchingIDs() {
        // La raison d'être du mécanisme : corriger une position fausse sans
        // passer par une soumission App Store.
        let merged = ContentMerge.merge(
            seed: [poi("a", title: "avant", x: 0.1), poi("b")],
            overlay: [poi("a", title: "après", x: 0.9)]
        )
        #expect(merged.count == 2)
        #expect(merged[0].title.en == "après")
        #expect(merged[0].position?.x == 0.9)
        #expect(merged[1].id == "b")
    }

    @Test func overlayAppendsEntriesAbsentFromTheSeed() {
        let merged = ContentMerge.merge(seed: [poi("a")], overlay: [poi("neuf")])
        #expect(merged.map(\.id) == ["a", "neuf"])
    }

    @Test func aTombstoneRemovesTheSeedEntry() {
        // Impossible de retirer du binaire ce qui y est compilé : la pierre
        // tombale est le seul moyen.
        let merged = ContentMerge.merge(
            seed: [poi("a"), poi("b")],
            overlay: [poi("a", deleted: true)]
        )
        #expect(merged.map(\.id) == ["b"])
    }

    @Test func aTombstoneMatchingNothingIsNotSurfaced() {
        let merged = ContentMerge.merge(seed: [poi("a")], overlay: [poi("fantôme", deleted: true)])
        #expect(merged.map(\.id) == ["a"])
    }

    @Test func aDeletedSeedEntryIsDroppedEvenWithoutAnOverlay() {
        #expect(ContentMerge.merge(seed: [poi("a", deleted: true), poi("b")], overlay: []).map(\.id) == ["b"])
    }

    @Test func seedOrderIsPreservedSoTheUIDoesNotReshuffleOnSync() {
        let seed = (1...5).map { poi("s\($0)") }
        let overlay = [poi("s3", title: "patché"), poi("neuf")]
        let merged = ContentMerge.merge(seed: seed, overlay: overlay)
        #expect(merged.map(\.id) == ["s1", "s2", "s3", "s4", "s5", "neuf"])
        #expect(merged[2].title.en == "patché")
    }

    @Test func aDuplicatedOverlayIDIsArbitratedNotDuplicated() {
        // Un bundle mal formé ne doit pas faire échouer la fusion, seulement
        // être arbitré — dernier gagnant.
        let merged = ContentMerge.merge(
            seed: [],
            overlay: [poi("a", title: "premier"), poi("a", title: "dernier")]
        )
        #expect(merged.count == 1)
        #expect(merged[0].title.en == "dernier")
    }

    @Test func mergesCollectionsToo() {
        // Le mécanisme est générique : c'est ce qui permettra de déclarer une
        // collection GTA VI sans mise à jour de l'app.
        let seed = [POICollection(id: "a", game: .reference, title: text("A"), isChallenge: true, expectedCount: 10)]
        let overlay = [
            POICollection(id: "a", game: .reference, title: text("A"), isChallenge: true, expectedCount: 12),
            POICollection(id: "leo", game: .leonida, title: text("Leo"), isChallenge: true),
        ]
        let merged = ContentMerge.merge(seed: seed, overlay: overlay)
        #expect(merged.map(\.id) == ["a", "leo"])
        #expect(merged[0].expectedCount == 12)
    }
}

struct ContentBundleTests {
    /// Le format que `content-cli publish` écrit dans `content_bundles` et que
    /// `ChunkedContentRepository` relit. Les deux côtés doivent s'accorder sur
    /// `collection`, `chunk` et `items`, sinon l'app lit du vide sans erreur.
    @Test func decodesTheShapeWrittenByTheCLI() throws {
        let json = Data("""
        {"collection":"poi_gtav","chunk":2,
         "items":[{"id":"poi_a","category":"landmark","position":{"x":0.5,"y":0.5},"title":{"en":"A"}}]}
        """.utf8)
        let bundle = try JSONDecoder().decode(ContentBundle<POI>.self, from: json)
        #expect(bundle.collection == "poi_gtav")
        #expect(bundle.chunk == 2)
        #expect(bundle.items.map(\.id) == ["poi_a"])
    }

    @Test func decodesAnEmptyChunk() throws {
        let json = Data(#"{"collection":"poi","chunk":0,"items":[]}"#.utf8)
        #expect(try JSONDecoder().decode(ContentBundle<POI>.self, from: json).items.isEmpty)
    }

    /// La taille de fragment est dupliquée entre le CLI et l'app (le client trie
    /// par `chunk` et concatène, il ne devine pas la taille). Ce test fige la
    /// valeur côté Swift pour que la dérive se voie.
    @Test func chunkSizeStaysAlignedWithTheCLI() {
        #expect(ContentBundle<POI>.chunkSize == 500)
    }
}
