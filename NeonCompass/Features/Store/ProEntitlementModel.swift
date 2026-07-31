import Foundation
import Observation

@Observable
@MainActor
final class ProEntitlementModel {
    private(set) var isProEntitled = false

    private let provider: ProEntitlementProviding
    // Un jeton d'annulation n'est pas de l'état de vue : `@ObservationIgnored`
    // le sort du suivi. Sans lui, la macro @Observable en faisait une propriété
    // CALCULÉE, sur laquelle `nonisolated(unsafe)` n'a aucun effet — d'où
    // l'avertissement du compilateur, qui pointait le symptôme et pas la cause
    // (et dont le remède suggéré, `nonisolated`, est interdit sur une propriété
    // stockée mutable).
    //
    // `nonisolated(unsafe)` reste nécessaire une fois la propriété redevenue
    // stockée : deinit s'exécute hors isolation même pour une classe @MainActor
    // (pas d'isolated-deinit dans le mode Swift de ce projet), donc l'annulation
    // ne doit pas exiger de saut d'acteur. `Task` est Sendable et `.cancel()`
    // s'appelle depuis n'importe quelle isolation : usage bénin, pas une course.
    @ObservationIgnored private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init(provider: ProEntitlementProviding) {
        self.provider = provider
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await isEntitled in provider.entitlementUpdates {
                self.isProEntitled = isEntitled
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isProEntitled = await provider.currentEntitlement()
    }

    func purchase() async {
        isProEntitled = (try? await provider.purchase()) ?? isProEntitled
    }

    func restorePurchases() async {
        isProEntitled = (try? await provider.restorePurchases()) ?? isProEntitled
    }
}
