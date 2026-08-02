import SwiftUI

/// Ce que la carte et la feuille de détail affichent, composé au même endroit.
///
/// Les deux vues rendent les mêmes lignes ; sans ce fichier, la composition de
/// « 2× GTA$ & RP » existerait en double et dériverait au premier ajustement.
///
/// Aucun de ces textes ne vient du contenu : le contenu porte des nombres et une
/// énumération, l'interface porte les mots. C'est ce qui permet d'écrire « GTA$ »
/// — la désignation officielle de la monnaie — là où un champ de contenu rédigé
/// se ferait refuser par `check-publishable`.
enum OnlineEventFormatting {
    /// Icônes de section. SF Symbols uniquement : aucun visuel importé, contrainte
    /// IP du projet.
    static let bonusesIcon = "arrow.up.right.circle.fill"
    static let discountsIcon = "tag.fill"
    static let rewardsIcon = "gift.fill"
    static let podiumIcon = "trophy.fill"
    static let highlightsIcon = "flame.fill"

    static func icon(for kind: OnlineEventRewardKind) -> String {
        switch kind {
        case .challenge: "flag.pattern.checkered"
        case .login: "door.left.hand.open"
        case .vehicle: "car.fill"
        case .cash: "banknote.fill"
        }
    }

    /// Clé de format du bonus. Quatre combinaisons, et pas de repli muet : un
    /// bonus sans valeur est refusé par le schéma ET par `assertBonusList`, donc
    /// s'il arrive ici c'est un contenu qui n'est pas passé par la chaîne — la
    /// ligne le dit plutôt que de s'afficher vide.
    static func label(for bonus: OnlineEventBonus) -> LocalizedStringKey {
        if let multiplier = bonus.multiplier {
            return bonus.includesRP
                ? "social.event.bonus.cashRP \(multiplier)"
                : "social.event.bonus.cash \(multiplier)"
        }
        if let percent = bonus.percentBonus {
            return bonus.includesRP
                ? "social.event.bonus.percentCashRP \(percent)"
                : "social.event.bonus.percentCash \(percent)"
        }
        return "social.event.bonus.unknown"
    }
}
