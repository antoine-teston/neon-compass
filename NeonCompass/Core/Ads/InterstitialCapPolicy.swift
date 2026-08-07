import Foundation

/// Pure decision logic for whether an interstitial may be shown right now —
/// no AdMob/UIKit import, unit-testable without a device (spec
/// §"Stratégie de tests": "plafonnement des interstitiels" is explicitly
/// called out as unit-testable logic).
enum InterstitialCapPolicy {
    /// - Parameters:
    ///   - sessionShownCount: how many interstitials have already been shown
    ///     this app session (0 at launch).
    ///   - isDuringContribution: true while a contribution submission sheet
    ///     is presented — never interrupt that flow (spec point, Plan 5b).
    ///   - serverFrequency: la fréquence pilotée par `app_config` — 0 éteint
    ///     entièrement les interstitiels (coupe-circuit), 1 signifie
    ///     « éligible » sous réserve du plafond de session ci-dessous, et les
    ///     valeurs supérieures à 1 sont réservées à un futur schéma « un sur N
    ///     moments éligibles » qui n'existe pas encore et sont donc traitées
    ///     comme 1.
    ///
    ///     Le paramètre s'appelait `remoteConfigFrequency`, du nom d'un outil
    ///     parti avec Firebase, et son commentaire annonçait que le renommage
    ///     attendrait le branchement de l'interstitiel. C'est ce branchement :
    ///     voir `InterstitialCoordinator`, qui est désormais son seul appelant.
    static func shouldShow(
        sessionShownCount: Int,
        isDuringContribution: Bool,
        serverFrequency: Int
    ) -> Bool {
        guard serverFrequency > 0 else { return false }
        guard !isDuringContribution else { return false }
        return sessionShownCount < 1
    }
}
