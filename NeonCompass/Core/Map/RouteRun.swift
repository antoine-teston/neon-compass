import Foundation

/// L'état d'une tournée en cours : l'ordre des étapes, FIGÉ à l'entrée en mode
/// (pas de recalcul — un recalcul re-proposerait immédiatement un point passé,
/// qui reste le plus proche), et l'index courant. Logique pure, aucun import UI.
///
/// Les étapes sont des identifiants de POI et non des POI : le POI vivant
/// (position, titre, état trouvé) se relit chez son propriétaire au moment de
/// l'affichage — la tournée n'a pas de copie à laisser se périmer.
struct RouteRun: Equatable, Sendable {
    /// Identifiants de POI, dans l'ordre du glouton.
    let steps: [String]
    private(set) var currentIndex: Int

    init(steps: [String]) {
        self.steps = steps
        self.currentIndex = 0
    }

    var isFinished: Bool { currentIndex >= steps.count }
    var currentStepID: String? { isFinished ? nil : steps[currentIndex] }
    /// « Étape n/N » — n en base 1, plafonné à N pour l'état terminé.
    var stepNumber: Int { min(currentIndex + 1, steps.count) }
    var totalSteps: Int { steps.count }

    /// Avance d'AU MOINS un cran — validation et saut avancent pareil, un
    /// point passé n'est jamais re-proposé — puis saute les étapes déjà
    /// trouvées par un autre chemin (fiche POI, synchro d'un autre appareil).
    mutating func advance(found: Set<String>) {
        guard !isFinished else { return }
        repeat {
            currentIndex += 1
        } while !isFinished && found.contains(steps[currentIndex])
    }
}
