import Testing
import Foundation
@testable import NeonCompass

struct POITests {
    @Test func resolvedFallsBackToEnglish() {
        let text = LocalizedText(en: "Lighthouse", fr: "Phare", es: nil, it: nil, de: nil)
        #expect(text.resolved(for: "fr") == "Phare")
        #expect(text.resolved(for: "es") == "Lighthouse")
        #expect(text.resolved(for: "en") == "Lighthouse")
    }

    @Test func decodesPOIArrayIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        [{
            "id": "poi_sample_lighthouse",
            "category": "landmark",
            "position": {"x": 0.7312, "y": 0.4147},
            "title": {"en": "Old Harbor Lighthouse", "fr": "Phare du vieux port"},
            "note": {"en": "Sample note"},
            "status": "draft",
            "sources": ["internal:fixture"]
        }]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois.count == 1)
        #expect(pois[0].id == "poi_sample_lighthouse")
        #expect(pois[0].category == .landmark)
        #expect(abs((pois[0].position?.x ?? -1) - 0.7312) < 0.0001)
        #expect(pois[0].title.resolved(for: "fr") == "Phare du vieux port")
    }

    @Test func decodesPOIWithNullPositionAsPending() throws {
        let json = Data("""
        [{
            "id": "poi_arts_center",
            "category": "landmark",
            "position": null,
            "title": {"en": "Arts Center", "fr": "Centre culturel des arts"},
            "note": {"en": "Sample note"},
            "status": "draft",
            "sources": ["internal:fixture"]
        }]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois.count == 1)
        #expect(pois[0].position == nil)
    }

    @Test func seedFileIsValidJSON() throws {
        // Vérifie que le fixture livré avec l'app est un JSON POI[] valide, en
        // lisant le fichier directement depuis le repo plutôt que via Bundle.main
        // (NeonCompassTests n'est pas hébergé dans le process app — TEST_HOST non
        // configuré — donc Bundle.main pointe vers le runner de test, pas l'app).
        // Le chargement réel via Bundle.main (POILoader.loadSeed) est couvert par
        // le build + la vérification visuelle de la Task 9.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NeonCompass/Resources/POI/seed-poi.json")
        let data = try Data(contentsOf: url)
        let pois = try POILoader.decode(data)
        #expect(pois.count >= 2)
    }
}
