import Foundation
import Testing
@testable import NeonCompass

/// Doublure d'`InterstitialAdProviding`. Compte les présentations plutôt que de
/// les simuler : ce qui est vérifié ici est une décision, pas un rendu.
private final class SpyInterstitialProvider: InterstitialAdProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _loadCount = 0
    private var _showCount = 0
    private var _isReady: Bool
    private let loadSucceeds: Bool

    init(isReadyInitially: Bool = false, loadSucceeds: Bool = true) {
        _isReady = isReadyInitially
        self.loadSucceeds = loadSucceeds
    }

    var loadCount: Int { lock.withLock { _loadCount } }
    var showCount: Int { lock.withLock { _showCount } }
    var isReady: Bool { lock.withLock { _isReady } }

    func load() async throws {
        lock.withLock { _loadCount += 1 }
        guard loadSucceeds else { throw URLError(.timedOut) }
        lock.withLock { _isReady = true }
    }

    @MainActor func show() async -> Bool {
        guard isReady else { return false }
        lock.withLock {
            _showCount += 1
            _isReady = false
        }
        return true
    }
}

private struct StubFrequency: InterstitialFrequencyProviding {
    var value: Int
    func frequency() async -> Int { value }
}

@MainActor
struct InterstitialCoordinatorTests {
    private func makeCoordinator(
        provider: SpyInterstitialProvider,
        frequency: Int = 1,
        isPro: Bool = false
    ) -> InterstitialCoordinator {
        InterstitialCoordinator(
            provider: provider,
            frequencyGate: StubFrequency(value: frequency),
            isProEntitled: { isPro },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test func aConsumedDetailShowsOneInterstitial() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 1)
    }

    /// La garde vit ICI et nulle part ailleurs : aucun site d'appel ne la
    /// connaît, donc aucun ne peut l'oublier. C'est la différence avec la
    /// bannière, où chaque écran teste `isProEntitled` de son côté.
    @Test func aProSubscriberNeverSeesAnything() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider, isPro: true)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
        #expect(provider.loadCount == 0)
    }

    @Test func frequencyZeroCutsEverything() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider, frequency: 0)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
    }

    @Test func theSessionCapHoldsAcrossSeveralDetails() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 1)
    }

    @Test func nothingIsShownDuringAContribution() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        coordinator.isDuringContribution = true
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
    }

    /// Un chargement raté ne présente rien, ne plante pas — et surtout ne
    /// relance pas en boucle : la règle AdMob sanctionne les requêtes
    /// excessives. Une tentative par moment éligible, pas plus.
    @Test func aFailedLoadShowsNothingAndDoesNotRetryInALoop() async {
        let provider = SpyInterstitialProvider(loadSucceeds: false)
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
        #expect(provider.loadCount == 2)
    }

    /// Le plafond se réarme par le cycle de vie de la scène, pas par le temps
    /// qui passe : c'est le même mécanisme que `InterstitialSession`, vu depuis
    /// son unique appelant.
    @Test func aLongBackgroundStayAllowsOneMoreInterstitial() async {
        let provider = SpyInterstitialProvider()
        let start = Date(timeIntervalSince1970: 1_000_000)
        // Horloge mobile : le passage en arrière-plan et le retour doivent être
        // séparés de plus de cinq minutes pour que le réarmement ait lieu.
        nonisolated(unsafe) var clock = start
        let coordinator = InterstitialCoordinator(
            provider: provider,
            frequencyGate: StubFrequency(value: 1),
            isProEntitled: { false },
            now: { clock }
        )
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()

        coordinator.didEnterBackground()
        clock = start.addingTimeInterval(600)
        coordinator.willEnterForeground()
        await coordinator.contentConsumed()

        #expect(provider.showCount == 2)
    }
}
