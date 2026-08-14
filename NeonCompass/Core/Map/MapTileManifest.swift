import Foundation

/// Décrit la pyramide de tuiles d'UNE carte : le manifeste de `MapArt/` décrit
/// l'espace de coordonnées des épingles et gouverne les deux cartes, celui-ci
/// décrit des fichiers et il y en a un par habillage.
///
/// Une carte sans manifeste n'est pas une anomalie : la carte de référence
/// (`island.png`, 4 096 px) n'a pas de pyramide et n'affiche que son socle.
/// C'est le repli normal, pas un filet — un seul chemin de rendu, une seule
/// condition.
struct MapTileManifest: Codable, Equatable, Sendable {
    struct Level: Codable, Equatable, Sendable {
        /// Côté du niveau en pixels — 9 216 ou 18 432 dans ce qui est livré.
        /// Ce type ne l'impose pas : c'est `MapTileResourcesTests` qui épingle
        /// les valeurs réelles, sur le vrai fichier.
        let side: Int
        /// Nombre de tuiles par côté, soit `side / tile`.
        let count: Int
        /// Tuiles d'une seule couleur, non livrées. Clé « x_y », valeur RRGGBB.
        let uniform: [String: String]
    }

    let tile: Int
    let base: Int
    /// Triés du plus grossier au plus fin — `MapTileSet` compte là-dessus pour
    /// prendre le premier niveau assez défini.
    let levels: [Level]

    static func load(for name: String, from bundle: Bundle = .main) -> MapTileManifest? {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "MapTiles"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapTileManifest.self, from: data)
    }

    /// La couleur d'une tuile omise, ou nil si la tuile est un fichier.
    ///
    /// Rend un entier plutôt qu'une couleur : ce type n'importe pas UIKit, ce
    /// qui le rend testable sans simulateur — et la conversion appartient à la
    /// couche, seule à savoir dans quel espace colorimétrique elle peint.
    func uniformColor(level: Int, x: Int, y: Int) -> UInt32? {
        guard let hex = levels.first(where: { $0.side == level })?.uniform["\(x)_\(y)"],
              let value = UInt32(hex, radix: 16) else { return nil }
        return value
    }
}
