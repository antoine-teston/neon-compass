import Foundation
import Supabase

/// Construit le client Supabase unique de l'app — ou rien.
///
/// « Ou rien » n'est pas un cas dégradé exotique : c'est l'état tant que le
/// projet Supabase n'existe pas, et l'état permanent des tests unitaires.
/// Aucune implémentation adossée au réseau n'est construite quand `shared` vaut
/// nil ; l'app retombe sur le socle embarqué et le cache SwiftData, exactement
/// comme elle le faisait quand `FirebaseApp.configure()` n'avait pas tourné.
///
/// **Ce que cette classe ne fait pas, et c'est le point.** Elle ne protège
/// aucune course. `Firestore.firestore()` et `RemoteConfig.remoteConfig()`
/// plantaient d'une erreur fatale NON RATTRAPABLE si l'app n'était pas
/// configurée — d'où `FirebaseAvailability`, les propriétés calculées de
/// `FirebaseClientAccountDeletion`, et la garde de `ContentSourceConfigurator`.
/// `SupabaseClient` est un objet ordinaire : mal configuré, il échoue par une
/// erreur Swift rattrapable au moment de la requête. La seule question qui
/// reste est « les identifiants existent-ils », et elle se tranche une fois,
/// paresseusement, au premier accès.
enum SupabaseClientProvider {
    /// Initialisé paresseusement et une seule fois par le runtime Swift.
    static let shared: SupabaseClient? = make()

    static var isConfigured: Bool { shared != nil }

    /// Valeur du gabarit versionné dans `Supabase-Info.plist`. Tant qu'elle est
    /// en place, on considère qu'il n'y a pas de projet — plutôt que de
    /// construire un client qui échouerait à chaque requête sur une URL
    /// invalide.
    private static let placeholder = "REMPLACER"

    static func make(bundle: Bundle = .main) -> SupabaseClient? {
        guard let plistURL = bundle.url(forResource: "Supabase-Info", withExtension: "plist"),
              let values = NSDictionary(contentsOf: plistURL) as? [String: String],
              let rawURL = usable(values["SUPABASE_URL"]),
              let url = URL(string: rawURL),
              let anonKey = usable(values["SUPABASE_ANON_KEY"])
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    private static func usable(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholder else { return nil }
        return trimmed
    }
}
