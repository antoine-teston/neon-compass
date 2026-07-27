import Foundation

/// Un fragment de collection publiée, tel qu'il est stocké dans Firestore sous
/// `content_bundles/{collection}_{chunk}`.
///
/// Pourquoi des agrégats plutôt qu'un document par entrée : Firestore facture
/// **une lecture par document**. Lire les POI un par un coûtait donc autant de
/// lectures qu'il y a de POI, à chaque changement de `contentVersion` — un
/// modèle qui tient à 500 entrées et explose quand le contenu du jeu à venir
/// bouge tous les jours. En agrégats, un client à jour lit ⌈N/500⌉ documents.
///
/// Pourquoi découpé plutôt qu'un seul document : un document Firestore est
/// plafonné à 1 MiB. À ~800 octets par entrée cinq langues remplies, le plafond
/// tomberait vers 1 300 entrées — atteignable. Le découpage retire le plafond du
/// tableau, et retire du même coup la raison principale de passer par un CDN.
struct ContentBundle<Item: ContentItem>: Codable, Sendable {
    let collection: String
    let chunk: Int
    let items: [Item]
}

extension ContentBundle {
    /// Nombre d'entrées par fragment. 500 × ~800 octets ≈ 400 Ko, soit une marge
    /// de deux fois et demie sous le plafond de 1 MiB.
    static var chunkSize: Int { 500 }
}
