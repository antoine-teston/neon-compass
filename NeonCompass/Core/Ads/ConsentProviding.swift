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
    func requestConsent() async throws -> Bool
}
