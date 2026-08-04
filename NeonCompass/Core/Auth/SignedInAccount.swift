import Foundation

/// De quel compte il s'agit — le fournisseur et, quand elle existe, l'adresse.
///
/// Les réglages ne le disaient nulle part : `AuthProviding` n'exposait que
/// `currentUserID`, donc un utilisateur connecté ne pouvait pas savoir avec
/// quel compte, ni quoi faire s'il en avait plusieurs.
///
/// Les adresses relais d'Apple (`@privaterelay.appleid.com`) s'affichent telles
/// quelles : c'est bien l'adresse du compte, et la masquer viderait la ligne de
/// ce qui la rend utile.
struct SignedInAccount: Equatable, Sendable {
    enum Provider: Equatable, Sendable {
        case apple, google, email
        /// Porté et non écarté : un fournisseur activé côté Supabase avant
        /// l'app ne doit pas faire disparaître la ligne d'identité.
        case other(String)

        static func from(_ raw: String?) -> Provider {
            switch raw?.lowercased() {
            case "apple": .apple
            case "google": .google
            case "email": .email
            case let value: .other(value ?? "")
            }
        }

        var labelKey: String {
            switch self {
            case .apple: "settings.account.provider.apple"
            case .google: "settings.account.provider.google"
            case .email: "settings.account.provider.email"
            case .other: "settings.account.provider.other"
            }
        }
    }

    let provider: Provider
    let email: String?
}
