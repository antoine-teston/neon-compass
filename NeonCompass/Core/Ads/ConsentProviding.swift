import Foundation

/// Abstraction over Google's User Messaging Platform (UMP) SDK — gates ad
/// serving on consent where required (EU/UK per Google's own region
/// detection), never bypassed (spec §RGPD: "Consentements pub (ATT/UMP) à
/// part" — this is a distinct, mandatory gate from account/profile consent).
protocol ConsentProviding: Sendable {
    /// Returns true once it's safe to request ads (either no consent was
    /// required for this user's region, or consent was obtained). Returns
    /// false if the user is in a region requiring consent and declined, or
    /// the consent flow could not complete.
    ///
    /// - Warning: any concrete conformance that presents UI (e.g. a consent
    ///   form) must isolate the WHOLE TYPE to `@MainActor`, not just this
    ///   method — a `nonisolated async` function called from a `@MainActor`
    ///   caller does not inherit that isolation, and SDKs that build UI
    ///   (e.g. UMP's `ConsentForm`, which constructs a `WKWebView`) will
    ///   crash at runtime if invoked off the main thread. This is not
    ///   hypothetical: `UMPConsentProvider`'s first implementation was
    ///   `nonisolated` and crashed under test for exactly this reason — see
    ///   its doc comment for the specific failure mode.
    func requestConsent() async throws -> Bool
}
