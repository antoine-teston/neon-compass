import SwiftUI

/// Comment une rubrique se montre : son libellé et son symbole.
///
/// Les deux `switch` vivaient en double, recopiés à l'identique dans la carte du
/// fil et dans l'écran d'article. La barre de filtres en aurait fait une
/// troisième copie — trois endroits où une rubrique ajoutée se traduirait par un
/// symbole manquant à un seul d'entre eux, sans que rien ne le signale.
extension NewsCategory {
    var titleKey: LocalizedStringKey {
        switch self {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        case .guide: "feed.category.guide"
        case .business: "feed.category.business"
        case .community: "feed.category.community"
        }
    }

    var symbolName: String {
        switch self {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        case .guide: "lightbulb"
        case .business: "tag"
        case .community: "person.2"
        }
    }
}

extension FeedPeriod {
    var titleKey: LocalizedStringKey {
        switch self {
        case .thisWeek: "feed.section.thisWeek"
        case .thisMonth: "feed.section.thisMonth"
        case .earlier: "feed.section.earlier"
        }
    }
}
