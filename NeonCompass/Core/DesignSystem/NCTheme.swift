import SwiftUI

/// Les habillages de l'app. Tous réutilisent les teintes de `NCColor` — aucune
/// couleur nouvelle n'entre par ici, et aucune ne porte le nom d'une palette
/// tierce.
///
/// **`classic` est le socle, les trois autres se paient** (arbitré le
/// 2026-08-19). Un thème gratuit qui serait l'un des trois nommés obligerait à
/// en amputer un de son fond et de son icône ; `classic` est au contraire
/// exactement ce que l'app a toujours été — fond `nightSky` uni, accent cyan,
/// icône primaire — donc l'utilisateur gratuit ne perd rien et le payant gagne
/// trois habillages entiers plutôt que deux. C'est aussi ce qui rend
/// `paywall.feature.themes` (« Thèmes exclusifs ») vrai au pluriel.
///
/// La gamme s'arrête à quatre. La charte n'a que cinq couleurs et ne tient que
/// parce qu'elle est courte : un cinquième thème ferait entrer une teinte hors
/// palette.
enum NCTheme: String, CaseIterable, Identifiable {
    case classic
    case magentaDrift
    case cyanPulse
    case sunsetOverdrive

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .classic: NCColor.neonCyan
        case .magentaDrift: NCColor.sunsetMagenta
        case .cyanPulse: NCColor.neonCyan
        case .sunsetOverdrive: NCColor.sunsetOrange
        }
    }

    /// `classic` et `cyanPulse` partagent leur accent, et c'est voulu : ce qui
    /// sépare le second du premier n'est pas la teinte mais le FOND d'ambiance
    /// et l'icône d'app qu'il apporte. Le distinguer par une quatrième couleur
    /// aurait demandé d'en inventer une, ce que le commentaire d'en-tête
    /// interdit.
    var isPro: Bool { self != .classic }

    /// Le fond d'ambiance, nommé dans le catalogue d'assets. Nul pour `classic`,
    /// qui est précisément l'absence de fond : l'aplat `nightSky`.
    ///
    /// C'est LUI le produit, pas l'accent. Sans fond, le Liquid Glass n'a rien à
    /// réfracter et le matériau ne se voit presque pas ; une nappe lumineuse
    /// derrière le fait exister sur tous les écrans à la fois, ce qu'une teinte
    /// de contrôle ne fait pas.
    var backdropName: String? {
        guard isPro else { return nil }
        return "backdrop-\(rawValue)"
    }

    /// L'icône alternée du catalogue. Nul pour `classic`, qui garde l'icône
    /// primaire — et `setAlternateIconName(nil)` est justement ce qui l'y
    /// ramène.
    ///
    /// AUCUNE de ces trois icônes n'est encore produite : le nom se résout donc
    /// dans le vide et UIKit échoue en silence, par son bloc de complétion. Voir
    /// `docs/ops/2026-08-19-banque-images-prompts-et-themes-pro.md` §5.4.
    var alternateIconName: String? {
        guard isPro else { return nil }
        return "AppIcon-\(rawValue.prefix(1).uppercased() + rawValue.dropFirst())"
    }

    var nameKey: LocalizedStringKey {
        switch self {
        case .classic: "theme.classic"
        case .magentaDrift: "theme.magentaDrift"
        case .cyanPulse: "theme.cyanPulse"
        case .sunsetOverdrive: "theme.sunsetOverdrive"
        }
    }
}
