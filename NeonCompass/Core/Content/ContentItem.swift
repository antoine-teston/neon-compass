import Foundation

/// Ce que `ContentStore` a besoin de savoir d'un type de contenu pour fusionner
/// un socle embarqué avec un overlay distant : une identité, et la capacité de
/// se déclarer retiré.
///
/// Le socle embarqué (`seed-poi.json`, `collections.json`) est figé dans le
/// binaire. Sans overlay, corriger une position fausse imposerait une
/// soumission App Store — deux à sept jours pour déplacer un pin. L'overlay
/// distant écrase par identifiant ; la pierre tombale est le seul moyen d'en
/// **retirer** une entrée, puisqu'on ne peut pas retirer du binaire ce qui y est
/// déjà compilé.
protocol ContentItem: Codable, Sendable, Identifiable where ID == String {
    /// Vrai pour une pierre tombale : l'entrée existe dans l'overlay uniquement
    /// pour annuler celle du socle.
    var isDeleted: Bool { get }
}

extension ContentItem {
    /// Les collections purement distantes (cheats, guides, actu, trophées)
    /// n'ont pas de socle : leur bundle est reconstruit intégralement à chaque
    /// publication, donc ne plus publier un document suffit à le faire
    /// disparaître. Elles n'ont aucun besoin de pierres tombales.
    var isDeleted: Bool { false }
}

extension Cheat: ContentItem {}
extension Guide: ContentItem {}
extension NewsItem: ContentItem {}
extension OnlineEvent: ContentItem {}
extension Trophy: ContentItem {}
