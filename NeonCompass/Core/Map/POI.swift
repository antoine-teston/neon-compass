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
    /// Ensemble nommé auquel ce POI appartient (`letter_scrap`, `garage`, …).
    /// C'est l'unité de compte d'un défi — la catégorie, elle, ne sert qu'au
    /// filtrage de la carte et à la couleur du pin. Optionnel : un POI sans
    /// collection s'affiche sur la carte et ne compte dans aucun défi, ce qui
    /// est l'état par défaut du contenu GTA VI tant qu'il n'est pas caractérisé.
    let collection: String?
    let position: NormalizedPoint?
    let title: LocalizedText
    let note: LocalizedText?
    /// Renseigné quand ce POI s'est révélé être un doublon d'un autre : la
    /// progression enregistrée sur cet id est recomptée sur sa cible. Supprimer
    /// purement et simplement le doublon ferait perdre leur progression à tous
    /// ceux qui l'avaient coché.
    let mergedInto: String?

    /// Explicite plutôt que synthétisé : Swift ne donne pas de valeur par défaut
    /// aux optionnels déclarés `let`, et sans ça chaque site de construction
    /// devrait passer `collection:` et `mergedInto:` à la main.
    init(
        id: String,
        category: POICategory,
        collection: String? = nil,
        position: NormalizedPoint?,
        title: LocalizedText,
        note: LocalizedText? = nil,
        mergedInto: String? = nil
    ) {
        self.id = id
        self.category = category
        self.collection = collection
        self.position = position
        self.title = title
        self.note = note
        self.mergedInto = mergedInto
    }
}

enum POILoader {
    enum LoaderError: Error { case missingResource }

    static func decode(_ data: Data) throws -> [POI] {
        try JSONDecoder().decode([POI].self, from: data)
    }

    /// Le repli sans sous-dossier n'est pas cosmétique : selon que
    /// `Resources/POI` est déclaré `type: folder` ou non dans project.yml,
    /// XcodeGen place le fichier dans `POI/` ou à plat à la racine du bundle.
    /// La variante folder est celle attendue (voir project.yml), mais un
    /// lookup qui échoue ici vide silencieusement la carte de tous ses POI —
    /// trop coûteux pour dépendre d'un seul chemin.
    static func loadSeed(from bundle: Bundle = .main) throws -> [POI] {
        let url = bundle.url(forResource: "seed-poi", withExtension: "json", subdirectory: "POI")
            ?? bundle.url(forResource: "seed-poi", withExtension: "json")
        guard let url else { throw LoaderError.missingResource }
        return try decode(Data(contentsOf: url))
    }

    /// Fixture embarquée, décodée paresseusement une seule fois pour tout le
    /// processus. La carte ET l'écran de progression en ont besoin : sans ce
    /// partage, chacun refaisait son propre parse de 143 Ko.
    static let bundled: [POI] = (try? loadSeed()) ?? []
}
