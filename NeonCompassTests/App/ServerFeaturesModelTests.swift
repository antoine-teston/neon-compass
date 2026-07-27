import Testing
@testable import NeonCompass

private final class StubGate: ServerFeatureGateProviding, @unchecked Sendable {
    var enabled = true
    var errorToThrow: Error?

    func isEnabled() async throws -> Bool {
        if let errorToThrow { throw errorToThrow }
        return enabled
    }
}

private struct Offline: Error {}

@MainActor
struct ServerFeaturesModelTests {
    /// L'app doit s'ouvrir sur l'état sûr : afficher des écrans de compte avant
    /// de savoir si le serveur existe, c'est promettre ce qu'on ne peut pas
    /// tenir pendant tout le premier rafraîchissement.
    @Test func startsDisabledBeforeAnyRefresh() {
        #expect(ServerFeaturesModel(gate: StubGate()).isEnabled == false)
    }

    @Test func enablesWhenTheGateSaysSo() async {
        let gate = StubGate()
        gate.enabled = true
        let model = ServerFeaturesModel(gate: gate)

        await model.refresh()

        #expect(model.isEnabled)
    }

    /// Le contraste avec le coupe-circuit communautaire est délibéré : celui-là
    /// échoue ouvert (capacité qui existe, qu'on éteint en cas d'abus), celui-ci
    /// échoue fermé (capacité qui n'existe pas encore).
    @Test func failsClosedWhenTheGateCannotBeReached() async {
        let gate = StubGate()
        gate.enabled = true
        gate.errorToThrow = Offline()
        let model = ServerFeaturesModel(gate: gate)

        await model.refresh()

        #expect(model.isEnabled == false)
    }

    @Test func turnsBackOffWhenTheFlagIsRevoked() async {
        let gate = StubGate()
        gate.enabled = true
        let model = ServerFeaturesModel(gate: gate)
        await model.refresh()
        #expect(model.isEnabled)

        gate.enabled = false
        await model.refresh()

        #expect(model.isEnabled == false)
    }
}
