import Foundation

/// Miroir de `content/schema/collection.schema.json`.
///
/// Une collection est un ensemble nommé de POI — les 50 fragments de lettre,
/// les 157 stations-service. C'est l'unité de compte d'un défi, à la place des
/// six `POICategory` : celles-ci mélangent 50 fragments, 50 pièces de vaisseau
/// et 30 déchets nucléaires dans un même tas « collectible », alors qu'un
/// joueur poursuit chaque ensemble séparément.
struct POICollection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let game: MapGame
    let title: LocalizedText
    let note: LocalizedText?

    /// Faux pour un simple regroupement de carte (stations-service, garages) :
    /// la collection n'apparaît pas du tout dans la progression. « Compléter »
    /// les stations-service ne veut rien dire.
    let isChallenge: Bool

    /// Nombre réel d'éléments **dans le jeu**, pas dans nos données. Diviser par
    /// ce qu'on a référencé afficherait « 100 % » à quelqu'un dont la partie est
    /// incomplète, et ferait régresser sa progression dès qu'un sync ajoute un
    /// POI.
    ///
    /// `nil` quand le total est encore inconnu : l'app affiche alors un décompte
    /// sans pourcentage. C'est l'état prévu pour GTA VI au lancement, où
    /// personne ne connaîtra les totaux avant plusieurs semaines.
    let expectedCount: Int?

    /// Pierre tombale, comme sur `POI` : le catalogue est embarqué, donc retirer
    /// une collection sans mise à jour de l'app demande de l'annuler depuis
    /// l'overlay.
    let deleted: Bool?

    /// Explicite pour la même raison que celui de `POI` : Swift ne donne pas de
    /// valeur par défaut aux optionnels déclarés `let`.
    init(
        id: String,
        game: MapGame,
        title: LocalizedText,
        note: LocalizedText? = nil,
        isChallenge: Bool,
        expectedCount: Int? = nil,
        deleted: Bool? = nil
    ) {
        self.id = id
        self.game = game
        self.title = title
        self.note = note
        self.isChallenge = isChallenge
        self.expectedCount = expectedCount
        self.deleted = deleted
    }
}

extension POICollection: ContentItem {
    var isDeleted: Bool { deleted == true }
}

enum POICollectionLoader {
    enum LoaderError: Error { case missingResource }

    static func decode(_ data: Data) throws -> [POICollection] {
        try JSONDecoder().decode([POICollection].self, from: data)
    }

    /// Même double lookup que `POILoader.loadSeed`, et pour la même raison :
    /// selon que `Resources/POI` est déclaré `type: folder` ou non dans
    /// project.yml, XcodeGen place le fichier dans `POI/` ou à plat.
    static func loadSeed(from bundle: Bundle = .main) throws -> [POICollection] {
        let url = bundle.url(forResource: "collections", withExtension: "json", subdirectory: "POI")
            ?? bundle.url(forResource: "collections", withExtension: "json")
        guard let url else { throw LoaderError.missingResource }
        return try decode(Data(contentsOf: url))
    }

    /// Catalogue embarqué, décodé une seule fois. Rejoindra le canal de contenu
    /// distant (`ContentStore`) quand les collections GTA VI existeront ; le
    /// type est un simple `Codable`, la bascule tiendra en une ligne.
    static let bundled: [POICollection] = (try? loadSeed()) ?? []
}
