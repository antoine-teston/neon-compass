import Foundation

/// Le jeu dont parle un contenu.
///
/// Type unique pour la carte, le fil d'actu et les codes. Les trois nommaient
/// la même distinction, et deux d'entre eux avaient déjà leur propre
/// énumération — `MapGame` et `NewsGame`, aux valeurs brutes identiques — alors
/// même que le commentaire de la seconde affirmait réutiliser le vocabulaire de
/// la première. Ajouter une troisième copie pour les codes aurait consacré la
/// dérive ; les deux noms existants sont devenus des alias de ce type.
///
/// Les libellés exposés à l'UI sont des chiffres romains nus, jamais la marque
/// elle-même : CLAUDE.md interdit les marques déposées dans l'app.
///
/// Les valeurs brutes sont celles du contenu (`content/schema/*.json`), pas les
/// noms de cas : `reference` se lit bien dans le code — « la carte de
/// référence » — mais ne veut rien dire dans le dépôt de contenu, où `gtav` est
/// explicite.
///
/// Le décodage est strict, délibérément. La tolérance aux valeurs inconnues que
/// portait `NewsGame` vit désormais au site d'appel qui la veut
/// (`NewsItem.init(from:)`) : appliquée ici, elle aurait fait ranger en silence
/// sous GTA VI toute collection de carte dont la valeur serait illisible, là où
/// un rejet bruyant est préférable.
enum Game: String, Codable, CaseIterable, Identifiable, Sendable {
    case leonida
    case reference = "gtav"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .leonida: "VI"
        case .reference: "V"
        }
    }
}
