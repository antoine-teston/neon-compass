import Foundation

/// Ce qu'une épingle personnelle représente, en six choix fixes.
///
/// Six et non un catalogue libre : la palette néon appartient aux catégories
/// éditoriales, et la lecture « telle couleur = telle catégorie » est ce qui
/// rend la carte lisible. Les épingles personnelles partagent donc toutes la
/// même teinte, et c'est le GLYPHE qui les distingue — même raisonnement que
/// `POIPinPalette`, où le symbole porte l'information et la couleur la renforce.
///
/// Les libellés sont génériques et ne nomment aucune marque : le CLAUDE.md
/// interdit les marques déposées partout où nous rédigeons nous-mêmes.
enum PersonalPinIcon: String, CaseIterable, Codable, Sendable {
    case marker, vehicle, photo, stash, danger, explore

    var symbol: String {
        switch self {
        case .marker: "mappin"
        case .vehicle: "car.fill"
        case .photo: "camera.fill"
        case .stash: "shippingbox.fill"
        case .danger: "exclamationmark.triangle.fill"
        case .explore: "questionmark"
        }
    }

    var labelKey: String.LocalizationValue {
        switch self {
        case .marker: "map.pins.icon.marker"
        case .vehicle: "map.pins.icon.vehicle"
        case .photo: "map.pins.icon.photo"
        case .stash: "map.pins.icon.stash"
        case .danger: "map.pins.icon.danger"
        case .explore: "map.pins.icon.explore"
        }
    }

    /// Décodage TOLÉRANT, à l'inverse de `Game`.
    ///
    /// La raison de la différence : `Game` décode du contenu que nous
    /// produisons, où une valeur illisible est un défaut de publication qu'il
    /// vaut mieux entendre. Ici la valeur vient du disque du joueur, et le
    /// chantier 2 la fera venir d'un autre appareil, possiblement plus récent.
    /// Refuser de décoder y ferait disparaître une épingle ; se rabattre sur le
    /// repère générique n'en abîme que l'illustration.
    static func from(rawValue: String) -> PersonalPinIcon {
        PersonalPinIcon(rawValue: rawValue) ?? .marker
    }
}
