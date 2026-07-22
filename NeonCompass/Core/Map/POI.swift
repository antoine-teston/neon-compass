import Foundation
import SwiftUI

enum POICategory: String, CaseIterable, Codable, Sendable {
    case landmark, collectible, activity, safehouse, vehicle, event

    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .landmark: "map.category.landmark"
        case .collectible: "map.category.collectible"
        case .activity: "map.category.activity"
        case .safehouse: "map.category.safehouse"
        case .vehicle: "map.category.vehicle"
        case .event: "map.category.event"
        }
    }
}

struct NormalizedPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

/// Miroir du schéma `content/schema/poi.schema.json` $defs.localized :
/// EN obligatoire, les autres langues optionnelles avec repli sur EN.
struct LocalizedText: Codable, Equatable, Sendable {
    let en: String
    let fr: String?
    let es: String?
    let it: String?
    let de: String?

    func resolved(for languageCode: String) -> String {
        switch languageCode {
        case "fr": fr ?? en
        case "es": es ?? en
        case "it": it ?? en
        case "de": de ?? en
        default: en
        }
    }
}

/// Champs pipeline-only du schéma (`status`, `sources`) sont absents ici :
/// Codable ignore silencieusement les clés JSON inconnues au décodage.
struct POI: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: POICategory
    let position: NormalizedPoint
    let title: LocalizedText
    let note: LocalizedText?
}

enum POILoader {
    enum LoaderError: Error { case missingResource }

    static func decode(_ data: Data) throws -> [POI] {
        try JSONDecoder().decode([POI].self, from: data)
    }

    static func loadSeed(from bundle: Bundle = .main) throws -> [POI] {
        guard let url = bundle.url(forResource: "seed-poi", withExtension: "json", subdirectory: "POI") else {
            throw LoaderError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }
}
