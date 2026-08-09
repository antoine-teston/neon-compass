import Foundation

/// Ce que le lecteur a déjà eu sous les yeux, d'une session à l'autre.
///
/// Des identifiants et non une date de dernière visite, et c'est ce qui rend le
/// repère fiable : `publishedAt` est daté au JOUR. Une entrée publiée à 14 h,
/// comparée à une visite de 10 h le même jour, se lirait comme antérieure à
/// celle-ci et n'apparaîtrait jamais comme neuve. Un identifiant absent du
/// magasin est neuf, quelle que soit l'heure.
///
/// L'ensemble est REMPLACÉ à chaque enregistrement, pas fusionné : il reste
/// donc borné par la taille du fil au lieu de croître indéfiniment. Une entrée
/// dépubliée puis republiée redeviendrait neuve — ce que le fil ne fait pas, et
/// qui serait de toute façon le bon comportement.
struct FeedSeenStore {
    private static let key = "feed.seenItemIDs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Faux au tout premier lancement, et seulement là.
    ///
    /// C'est la garde qui évite le pire départ possible : sans elle, la première
    /// synchronisation d'un fil de quarante-six entrées les marquerait toutes
    /// comme neuves, et le repère ne voudrait plus rien dire au moment précis où
    /// on le découvre.
    var hasRecordedASession: Bool {
        defaults.object(forKey: Self.key) != nil
    }

    var seenIDs: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func record(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: Self.key)
    }
}
