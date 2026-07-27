import Foundation

/// Fusion du socle embarqué avec l'overlay distant.
///
/// Le socle (`seed-poi.json`, `collections.json`) est compilé dans le binaire :
/// disponible au premier lancement, sans réseau, sans coût de lecture. Mais il
/// est aussi figé — sans overlay, corriger une position fausse imposerait une
/// soumission App Store, soit deux à sept jours pour déplacer un pin.
///
/// Fonction pure et isolée pour être testable sans SwiftData ni Firestore.
enum ContentMerge {
    /// - Parameters:
    ///   - seed: entrées embarquées, base de la fusion.
    ///   - overlay: entrées distantes. Écrasent le socle à identifiant égal, et
    ///     ajoutent les nouvelles.
    /// - Returns: le socle patché, dans l'ordre du socle puis des ajouts, pour
    ///   que l'affichage ne se réordonne pas à chaque sync.
    static func merge<Item: ContentItem>(seed: [Item], overlay: [Item]) -> [Item] {
        guard !overlay.isEmpty else { return seed.filter { !$0.isDeleted } }

        var patches: [String: Item] = [:]
        // Dernier gagnant à identifiant dupliqué dans l'overlay : un bundle mal
        // formé ne doit pas faire échouer la fusion, seulement être arbitré.
        for item in overlay { patches[item.id] = item }

        var merged: [Item] = []
        merged.reserveCapacity(seed.count + overlay.count)
        var consumed = Set<String>()

        for item in seed {
            if let patch = patches[item.id] {
                consumed.insert(item.id)
                guard !patch.isDeleted else { continue }
                merged.append(patch)
            } else if !item.isDeleted {
                merged.append(item)
            }
        }

        // Les entrées de l'overlay absentes du socle sont des ajouts. Une pierre
        // tombale sans entrée correspondante ne désigne rien : on ne la reporte
        // pas. `patches` a déjà arbitré les identifiants dupliqués, et le Set
        // garantit qu'on n'ajoute le gagnant qu'une fois.
        var appended = Set<String>()
        for item in overlay where !consumed.contains(item.id) && !item.isDeleted {
            guard appended.insert(item.id).inserted else { continue }
            merged.append(patches[item.id] ?? item)
        }

        return merged
    }
}
