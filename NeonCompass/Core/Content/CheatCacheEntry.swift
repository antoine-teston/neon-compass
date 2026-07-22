import Foundation
import SwiftData

/// Cache SwiftData d'une collection de contenu entière, sérialisée en JSON.
/// v1 : granularité "toute la collection" (pas de delta par document) —
/// suffisant tant que le volume de contenu reste modeste (spec §7 : le
/// pipeline de contenu vise des dizaines à quelques centaines d'entrées).
@Model
final class CheatCacheEntry {
    @Attribute(.unique) var collectionName: String
    var json: Data
    var version: Int

    init(collectionName: String, json: Data, version: Int) {
        self.collectionName = collectionName
        self.json = json
        self.version = version
    }
}
