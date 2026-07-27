import Testing
import Foundation
@testable import NeonCompass

struct MapManifestTests {
    @Test func decodesManifest() throws {
        let json = Data("""
        {"size": 2048, "source": "island-placeholder.svg", "sourceSha256": "abc123"}
        """.utf8)
        let manifest = try JSONDecoder().decode(MapManifest.self, from: json)
        #expect(manifest.size == 2048)
    }
}
