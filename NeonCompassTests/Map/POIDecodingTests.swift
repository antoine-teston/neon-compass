import Foundation
import Testing
@testable import NeonCompass

struct POIDecodingTests {
    /// Le format de tous les documents Firestore publiés à ce jour : ni
    /// `collection` ni `mergedInto`. Les deux champs sont arrivés après eux et
    /// doivent rester facultatifs, sinon un sync viderait la carte.
    @Test func decodesADocumentWithoutTheNewFields() throws {
        let json = Data("""
        [{"id":"poi_x","category":"landmark","position":{"x":0.5,"y":0.5},"title":{"en":"X"}}]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois.count == 1)
        #expect(pois[0].collection == nil)
        #expect(pois[0].mergedInto == nil)
    }

    @Test func decodesTheNewFieldsWhenPresent() throws {
        let json = Data("""
        [{"id":"poi_x","category":"collectible","collection":"letter_scrap",
          "position":{"x":0.5,"y":0.5},"title":{"en":"X"},"mergedInto":"poi_y"}]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois[0].collection == "letter_scrap")
        #expect(pois[0].mergedInto == "poi_y")
    }

    /// Les champs pipeline-only (`status`, `sources`, `processedFrom`) sont
    /// présents dans la fixture embarquée mais absents du modèle : le décodage
    /// doit continuer de les ignorer en silence.
    @Test func ignoresPipelineOnlyFields() throws {
        let json = Data("""
        [{"id":"poi_x","category":"landmark","collection":"gas","position":{"x":0.5,"y":0.5},
          "title":{"en":"X"},"status":"draft","sources":["u"],"processedFrom":"k"}]
        """.utf8)
        #expect(try POILoader.decode(json).count == 1)
    }

    @Test func decodesTheBundledCollectionCatalogue() throws {
        let json = Data("""
        [{"id":"letter_scrap","game":"gtav","title":{"en":"Letter Scraps"},
          "isChallenge":true,"expectedCount":50,"status":"draft","sources":["u"]},
         {"id":"gas","game":"gtav","title":{"en":"Gas Stations"},
          "isChallenge":false,"status":"draft","sources":["u"]}]
        """.utf8)
        let collections = try POICollectionLoader.decode(json)
        #expect(collections.count == 2)
        // `gtav` est la valeur du contenu, `reference` le nom du cas côté code.
        #expect(collections[0].game == .reference)
        #expect(collections[0].expectedCount == 50)
        #expect(collections[1].isChallenge == false)
        #expect(collections[1].expectedCount == nil)
    }
}
