import Foundation
import Observation

/// Le seul endroit qui décide de montrer un interstitiel.
///
/// **Pourquoi un coordinateur plutôt qu'un appel direct depuis les écrans.**
/// Aucun onglet n'a de `NavigationStack`, et les détails ne sont même pas
/// présentés de la même façon d'une feature à l'autre : `NewsDetailView` est une
/// feuille, `POIDetailView` est construit à la volée dans `MapScreen`,
/// `CheatReaderView` est un `fullScreenCover`. Il n'existe aucun point de
/// passage unique à intercepter — il faut donc en fabriquer un.
///
/// Les écrans n'ont qu'une entrée, `contentConsumed()`, et ignorent tout du
/// plafond, de l'abonnement et du réglage serveur. Ce n'est pas de l'élégance :
/// `BannerAdView` ne se protège pas elle-même et c'est chaque écran qui teste
/// `isProEntitled`. Ce motif est tolérable pour une bannière, où un oubli se
/// voit tout de suite ; il ne l'est pas pour une pleine page servie à un client
/// payant.
///
/// **L'abonnement est lu par une fermeture, pas par une référence au modèle.**
/// `WidgetSummaryCoordinator` prend `ProEntitlementModel` directement ; ici la
/// fermeture permet de vérifier les sept décisions ci-contre sans construire
/// StoreKit, tout en gardant la garde à l'intérieur.
@Observable
@MainActor
final class InterstitialCoordinator {
    private let provider: any InterstitialAdProviding
    private let frequencyGate: any InterstitialFrequencyProviding
    private let isProEntitled: @MainActor () -> Bool
    private let now: @Sendable () -> Date

    private var session = InterstitialSession()
    private var frequency = SupabaseInterstitialFrequencyGate.defaultFrequency

    /// Vrai tant qu'une feuille de contribution est présentée. Le drapeau vit
    /// ici pour que `InterstitialCapPolicy` reste une fonction pure.
    var isDuringContribution = false

    init(
        provider: any InterstitialAdProviding = AdMobInterstitialProvider(),
        frequencyGate: any InterstitialFrequencyProviding = SupabaseInterstitialFrequencyGate(),
        isProEntitled: @escaping @MainActor () -> Bool,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.frequencyGate = frequencyGate
        self.isProEntitled = isProEntitled
        self.now = now
    }

    func refreshFrequency() async {
        frequency = await frequencyGate.frequency()
    }

    func didEnterBackground() {
        session.didEnterBackground(at: now())
    }

    func willEnterForeground() {
        session.willEnterForeground(at: now())
    }

    /// À appeler à la fermeture d'un écran de détail, et nulle part ailleurs.
    ///
    /// L'utilisateur a obtenu ce qu'il venait chercher et revient à une liste :
    /// c'est la pause naturelle qu'attend la règle AdMob. Jamais à l'entrée
    /// d'une tâche, jamais en pleine lecture.
    func contentConsumed() async {
        guard !isProEntitled() else { return }
        guard InterstitialCapPolicy.shouldShow(
            sessionShownCount: session.shownCount,
            isDuringContribution: isDuringContribution,
            serverFrequency: frequency
        ) else { return }

        if !provider.isReady {
            // Une seule tentative par moment éligible. Pas de reprise, pas de
            // boucle : la règle AdMob sanctionne les requêtes excessives.
            try? await provider.load()
        }
        guard provider.isReady else { return }
        if await provider.show() {
            session.recordShown()
        }
    }
}
