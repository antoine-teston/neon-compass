import Foundation

/// Décrit l'image de carte générée par tools/basemap/tile.js. Un seul champ
/// depuis le retrait de CATiledLayer (docs/superpowers/plans/2026-07-24-
/// plan-map-engine-rebuild.md) — plus de pyramide de tuiles à décrire.
struct MapManifest: Codable, Equatable, Sendable {
    let size: Int

    static func load(from bundle: Bundle = .main) -> MapManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MapArt"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapManifest.self, from: data)
    }
}
