import Foundation

/// Décrit une pyramide de tuiles générée par tools/basemap/tile.js.
/// Champs additionnels du JSON (source, sourceSha256) sont ignorés au décodage.
struct TileManifest: Codable, Equatable, Sendable {
    let tileSize: Int
    let maxZoom: Int
    let tileCount: Int

    static func load(from bundle: Bundle = .main) -> TileManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MapTiles"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TileManifest.self, from: data)
    }
}
