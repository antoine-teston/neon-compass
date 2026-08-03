import Foundation
import Testing
@testable import NeonCompass

/// Les deux portails ont des défauts OPPOSÉS, et c'est délibéré
/// (`docs/ops/2026-07-27-sans-blaze.md`). Se tromper de sens sur l'un n'affiche
/// rien ; se tromper sur l'autre affiche des écrans qui échouent, ou rallume
/// des contributions au pire moment. D'où une suite qui les fige tous les deux
/// sur les trois états qui comptent : ligne absente, ligne présente, source
/// illisible.
struct AppConfigGateTests {
    /// Trois comportements, un seul fake : rendre une valeur, n'avoir aucune
    /// ligne, ou échouer.
    private struct FakeConfig: AppConfigReading {
        enum Behaviour: Sendable {
            case values([String: Bool])
            case empty
            case unreadable
        }

        struct Unreachable: Error {}

        let behaviour: Behaviour

        func bool(_ key: String, default defaultValue: Bool) async throws -> Bool {
            switch behaviour {
            case .values(let values):
                return values[key] ?? defaultValue
            case .empty:
                return defaultValue
            case .unreadable:
                throw Unreachable()
            }
        }

        func string(_ key: String) async throws -> String? { nil }
        func int(_ key: String) async throws -> Int? { nil }
    }

    // MARK: - Portail des fonctionnalités serveur : défaut FERMÉ

    @Test func serverFeaturesAreOffWhenTheKeyIsAbsent() async throws {
        let gate = SupabaseServerFeatureGate(config: FakeConfig(behaviour: .empty))
        #expect(try await gate.isEnabled() == false)
    }

    @Test func serverFeaturesFollowAnExplicitTrue() async throws {
        let gate = SupabaseServerFeatureGate(
            config: FakeConfig(behaviour: .values([AppConfigKey.backendFeaturesEnabled: true]))
        )
        #expect(try await gate.isEnabled() == true)
    }

    @Test func serverFeaturesFollowAnExplicitFalse() async throws {
        let gate = SupabaseServerFeatureGate(
            config: FakeConfig(behaviour: .values([AppConfigKey.backendFeaturesEnabled: false]))
        )
        #expect(try await gate.isEnabled() == false)
    }

    // MARK: - Coupe-circuit communautaire : défaut OUVERT

    /// Le cas que `RemoteConfigCommunityGateProvider` devait attraper en
    /// inspectant `ConfigValue.source == .static`, faute de savoir distinguer
    /// « jamais posée » de « posée à faux ». Avec une table, l'absence de ligne
    /// est l'absence de ligne.
    @Test func communityContributionsStayOnWhenTheKeyIsAbsent() async throws {
        let gate = SupabaseCommunityGateProvider(config: FakeConfig(behaviour: .empty))
        #expect(try await gate.isEnabled() == true)
    }

    @Test func communityContributionsRespectTheKillSwitch() async throws {
        let gate = SupabaseCommunityGateProvider(
            config: FakeConfig(behaviour: .values([AppConfigKey.communityContributionsEnabled: false]))
        )
        #expect(try await gate.isEnabled() == false)
    }

    // MARK: - Une source illisible n'est PAS une absence

    /// Les deux portails doivent LEVER, pas rendre leur défaut.
    ///
    /// Pour le coupe-circuit c'est l'invariant qui compte le plus : rendre
    /// `true` sur erreur réseau rallumerait les contributions précisément
    /// pendant l'incident qui a motivé de les éteindre. `ServerFeaturesModel`
    /// traduit l'erreur en faux de son côté, ce qui est son droit — mais c'est
    /// sa décision, pas celle du portail.
    @Test func anUnreadableSourceThrowsRatherThanFallingBackToTheDefault() async throws {
        let serverGate = SupabaseServerFeatureGate(config: FakeConfig(behaviour: .unreadable))
        await #expect(throws: FakeConfig.Unreachable.self) { try await serverGate.isEnabled() }

        let communityGate = SupabaseCommunityGateProvider(config: FakeConfig(behaviour: .unreadable))
        await #expect(throws: FakeConfig.Unreachable.self) { try await communityGate.isEnabled() }
    }
}
