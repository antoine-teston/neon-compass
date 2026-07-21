import Testing
import Foundation
@testable import NeonCompass

struct TileManifestTests {
    @Test func decodesManifest() throws {
        let json = Data("""
        {"tileSize": 256, "maxZoom": 3, "tileCount": 85, "source": "leonida-placeholder.svg", "sourceSha256": "abc123"}
        """.utf8)
        let manifest = try JSONDecoder().decode(TileManifest.self, from: json)
        #expect(manifest.tileSize == 256)
        #expect(manifest.maxZoom == 3)
        #expect(manifest.tileCount == 85)
    }
}
