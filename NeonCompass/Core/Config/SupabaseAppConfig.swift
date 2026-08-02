import Foundation
import Supabase

/// Accès aux paramètres distants, abstrait du transport.
///
/// Existe pour une raison précise : les deux portails ont des défauts opposés
/// ET une sémantique d'erreur qui n'est pas celle d'une absence. Ces trois cas
/// — absent, présent, illisible — doivent pouvoir être exercés sans réseau,
/// sinon la seule chose qu'on teste est le chemin heureux.
protocol AppConfigReading: Sendable {
    /// `defaultValue` quand la clé n'a AUCUNE ligne. Lève si la source est
    /// illisible — ne jamais confondre les deux.
    func bool(_ key: String, default defaultValue: Bool) async throws -> Bool
    func string(_ key: String) async throws -> String?
    func int(_ key: String) async throws -> Int?
}

/// Lit la table `app_config` — le remplaçant de Remote Config.
///
/// Une seule lecture par session, partagée : les trois portails (contenu,
/// fonctionnalités serveur, coupe-circuit communautaire) tirent sur la même,
/// là où chacun appelait `fetchAndActivate()` de son côté.
///
/// **Ce que cette table règle et que Remote Config compliquait.** Les deux
/// portails ont des défauts OPPOSÉS voulus (voir `ServerFeatureGateProviding`) :
/// `backendFeaturesEnabled` absent vaut faux, `communityContributionsEnabled`
/// absent vaut vrai. Avec Remote Config, « absent » et « explicitement faux »
/// rendaient tous deux `boolValue == false`, et il fallait inspecter
/// `ConfigValue.source == .static` pour les distinguer — huit lignes de
/// commentaire d'excuse dans `RemoteConfigCommunityGateProvider`. Ici, absent
/// c'est « pas de ligne », et `value(for:)` rend `nil`.
///
/// **Un échec de lecture n'est PAS une absence.** Sur erreur réseau on relance,
/// on ne rend pas le défaut : sans quoi une coupure réseau rallumerait le
/// coupe-circuit communautaire, ce qui est exactement le moment où on ne le
/// veut pas. C'est la sémantique qu'avait déjà `fetchAndActivate()` en levant.
actor SupabaseAppConfig: AppConfigReading {
    static let shared = SupabaseAppConfig()

    private struct Row: Decodable {
        let key: String
        let value: AnyJSON
    }

    private let client: SupabaseClient?
    private var cached: [String: AnyJSON]?

    /// Mémorise la requête en cours, pas seulement son résultat : au lancement
    /// les trois portails demandent la configuration en même temps, et sans ça
    /// ils déclencheraient trois requêtes identiques.
    private var inFlight: Task<[String: AnyJSON], Error>?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Oublie ce qui est mémorisé. Le prochain accès relira la table.
    /// Réservé au rafraîchissement demandé par l'utilisateur, comme
    /// `ContentCDN.invalidateManifest()`.
    func invalidate() {
        cached = nil
        inFlight = nil
    }

    func bool(_ key: String, default defaultValue: Bool) async throws -> Bool {
        guard let value = try await value(for: key) else { return defaultValue }
        return value.boolValue ?? defaultValue
    }

    func string(_ key: String) async throws -> String? {
        try await value(for: key)?.stringValue
    }

    func int(_ key: String) async throws -> Int? {
        guard let value = try await value(for: key) else { return nil }
        return value.intValue
    }

    /// `nil` = aucune ligne pour cette clé. Lève si la table est illisible.
    private func value(for key: String) async throws -> AnyJSON? {
        try await values()[key]
    }

    private func values() async throws -> [String: AnyJSON] {
        if let cached { return cached }
        if let inFlight { return try await inFlight.value }

        guard let client else {
            // Pas de projet configuré : une configuration vide, et donc les
            // défauts de chaque portail. Ce n'est pas un échec — c'est l'état
            // normal des tests et d'un build sans identifiants.
            cached = [:]
            return [:]
        }

        let task = Task<[String: AnyJSON], Error> {
            let rows: [Row] = try await client
                .from("app_config")
                .select("key,value")
                .execute()
                .value
            return Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        inFlight = task

        do {
            let result = try await task.value
            cached = result
            inFlight = nil
            return result
        } catch {
            // Ne rien mémoriser : la prochaine tentative doit repartir du
            // réseau, pas d'un échec figé pour toute la session.
            inFlight = nil
            throw error
        }
    }
}

/// Clés de `app_config`. Regroupées ici pour que la liste des paramètres
/// distants soit lisible d'un coup d'œil, et pour qu'aucune chaîne ne soit
/// écrite deux fois de part et d'autre d'une frontière réseau.
enum AppConfigKey {
    static let contentBaseURL = "contentBaseURL"
    static let backendFeaturesEnabled = "backendFeaturesEnabled"
    static let communityContributionsEnabled = "communityContributionsEnabled"
    static let communitySpotsVersion = "communitySpotsVersion"
}
