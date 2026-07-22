import Foundation
import SwiftData

/// Cache SwiftData d'une collection de contenu entière, sérialisée en JSON.
/// Un seul type de modèle partagé entre tous les types de contenu
/// (POI, Cheat, Guide, ...), une ligne par `collectionName` — remplace les
/// trois `CacheEntry` dupliqués (POI/Cheat/Guide) qui ne différaient que
/// par leur nom de type.
/// v1 : granularité "toute la collection" (pas de delta par document) —
/// suffisant tant que le volume de contenu reste modeste (spec §7 : le
/// pipeline de contenu vise des dizaines à quelques centaines d'entrées).
@Model
final class ContentCacheEntry {
    @Attribute(.unique) var collectionName: String
    var json: Data
    var version: Int

    init(collectionName: String, json: Data, version: Int) {
        self.collectionName = collectionName
        self.json = json
        self.version = version
    }
}
