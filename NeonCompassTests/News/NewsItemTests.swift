import Testing
import Foundation
@testable import NeonCompass

struct NewsItemTests {
    @Test func decodesNewsItemIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "news_sample_patch",
            "category": "patch",
            "title": {"en": "Title update 1.1", "fr": "Mise à jour 1.1"},
            "body": {"en": "Sample patch notes, reworded in our own words."},
            "publishedAt": "2026-07-20",
            "status": "draft",
            "sources": ["internal:fixture"]
        }
        """.utf8)
        let newsItem = try JSONDecoder().decode(NewsItem.self, from: json)
        #expect(newsItem.id == "news_sample_patch")
        #expect(newsItem.category == .patch)
        #expect(newsItem.title.resolved(for: "fr") == "Mise à jour 1.1")
        #expect(newsItem.publishedAt == "2026-07-20")
    }

    private func item(_ fields: String) throws -> NewsItem {
        try JSONDecoder().decode(NewsItem.self, from: Data("""
        {
            "id": "news_x",
            "title": {"en": "T"},
            "body": {"en": "B"},
            "publishedAt": "2026-07-29"
            \(fields.isEmpty ? "" : ",\(fields)")
        }
        """.utf8))
    }

    /// Une rubrique inconnue ne fait PAS tomber le décodage.
    ///
    /// L'enjeu n'est pas cette entrée-là, c'est le fragment entier : les
    /// collections sont servies par lots, et `ContentBundle` décode le tableau
    /// d'un coup. Sans tolérance, publier une rubrique neuve viderait le fil de
    /// tous les clients pas encore mis à jour — sans qu'aucune erreur ne le
    /// dise. Ajouter une rubrique cesserait d'être possible avant que tout le
    /// parc ait basculé.
    @Test func anUnknownCategoryFallsBackInsteadOfThrowing() throws {
        let decoded = try item(#""category": "rubrique_du_futur""#)
        #expect(decoded.category == .announcement)
    }

    @Test func decodesTheWidenedCategorySet() throws {
        for (raw, expected): (String, NewsCategory) in [
            ("guide", .guide), ("business", .business), ("community", .community),
            ("announcement", .announcement), ("patch", .patch), ("event", .event),
        ] {
            #expect(try item(#""category": "\#(raw)""#).category == expected)
        }
    }

    /// Les entrées publiées avant l'ouverture du fil aux deux jeux ne portent pas
    /// de `game`. Elles concernaient toutes celui à venir : le défaut doit donc
    /// les afficher comme telles, et non les ranger du mauvais côté.
    @Test func aMissingGameMeansTheUpcomingOne() throws {
        let decoded = try item(#""category": "announcement""#)
        #expect(decoded.game == .leonida)
        #expect(decoded.game.shortLabel == "VI")
    }

    @Test func decodesTheCurrentGameAndLabelsItV() throws {
        let decoded = try item(#""category": "patch", "game": "gtav""#)
        #expect(decoded.game == .reference)
        #expect(decoded.game.shortLabel == "V")
    }

    @Test func anUnknownGameFallsBackInsteadOfThrowing() throws {
        let decoded = try item(#""category": "patch", "game": "gta4""#)
        #expect(decoded.game == .leonida)
    }

    @Test func decodesEveryConfidenceLevel() throws {
        for (raw, expected): (String, NewsConfidence) in [
            ("confirmed-official", .confirmedOfficial), ("multi-source", .multiSource),
            ("single-source", .singleSource), ("rumor", .rumor),
        ] {
            #expect(try item(#""category": "announcement", "confidence": "\#(raw)""#).confidence == expected)
        }
    }

    /// Un palier de confiance inconnu devient `nil`, il ne fait pas tomber le
    /// fragment.
    ///
    /// C'est la même exigence que sur la rubrique et le jeu, mais la réponse
    /// diffère : ici pas de repli sur une valeur par défaut, parce qu'un niveau
    /// de confiance inventé serait pire que pas de niveau. La vue n'affiche
    /// alors rien.
    @Test func anUnknownConfidenceBecomesNilInsteadOfThrowing() throws {
        let decoded = try item(#""category": "announcement", "confidence": "plutot-sur""#)
        #expect(decoded.confidence == nil)
    }

    @Test func anAbsentConfidenceIsNil() throws {
        #expect(try item(#""category": "announcement""#).confidence == nil)
    }

    /// Le vocabulaire du jeu doit rester celui de la carte. Deux énumérations
    /// pour la même distinction finissent toujours par diverger — ce test est le
    /// seul endroit où elles se regardent.
    @Test func theNewsGameVocabularyMatchesTheMapGameOne() {
        #expect(NewsGame.leonida.rawValue == MapGame.leonida.rawValue)
        #expect(NewsGame.reference.rawValue == MapGame.reference.rawValue)
        #expect(NewsGame.leonida.shortLabel == MapGame.leonida.shortLabel)
        #expect(NewsGame.reference.shortLabel == MapGame.reference.shortLabel)
    }
}
