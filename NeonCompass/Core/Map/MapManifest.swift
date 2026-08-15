import Foundation

/// Décrit l'image de carte générée par tools/basemap/tile.js. Un seul champ
/// depuis le retrait de CATiledLayer (docs/superpowers/plans/2026-07-24-
/// plan-map-engine-rebuild.md) — plus de pyramide de tuiles à décrire.
struct MapManifest: Codable, Equatable, Sendable {
    let size: Int

    /// UN seul manifeste gouverne les deux cartes, et `manifest-vi.json` n'est
    /// jamais lu — il n'accompagne l'image que comme trace de génération
    /// (source, empreinte, pixels). Ce n'est pas un oubli : `size` décrit
    /// l'espace de COORDONNÉES dans lequel les épingles sont normalisées, pas
    /// une propriété de telle ou telle image. Le rendre dépendant de la carte
    /// affichée donnerait deux référentiels et déplacerait les épingles en
    /// basculant de jeu.
    static func load(from bundle: Bundle = .main) -> MapManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MapArt"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapManifest.self, from: data)
    }
}
