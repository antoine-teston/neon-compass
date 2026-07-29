import Foundation

/// Manifeste du contenu servi par le CDN.
///
/// Il porte la version ET la carte des fragments : **un client à jour lit ce
/// seul fichier et s'arrête là**. C'est l'équivalent de la garde `contentVersion`
/// de Remote Config, en une requête HTTP au lieu d'un SDK.
struct ContentManifest: Decodable, Sendable {
    struct CollectionInfo: Decodable, Sendable {
        let chunks: Int
        let count: Int
    }

    let version: Int
    let commit: String?
    let collections: [String: CollectionInfo]
}

/// Accès au contenu statique, sans SDK.
///
/// Pourquoi un CDN plutôt que Firestore pour la lecture : le trafic de cette app
/// est à 95 % de la lecture de contenu partagé et versionné — une charge de
/// distribution de fichiers, pas une charge de base. Un JSON derrière une URL
/// coûte **zéro par lecture** (contre une lecture facturée par document),
/// répond depuis le cache en périphérie, et se lit identiquement depuis Swift,
/// Kotlin ou un navigateur. C'est ce dernier point qui compte le jour où un
/// second client existe.
///
/// Le manifeste est relu une fois par session au plus : les deux consommateurs
/// (garde de version et dépôt de fragments) le partagent, donc une
/// synchronisation ne fait pas deux fois la même requête.
actor ContentCDN {
    static let shared = ContentCDN()

    private var cachedManifest: ContentManifest?
    private var baseURL: URL?

    /// Configuré au lancement depuis Remote Config. Tant qu'il est nil, tout
    /// retombe sur Firestore — c'est ce qui rend la bascule réversible sans
    /// mise à jour de l'app.
    func configure(baseURL: URL?) {
        guard baseURL != self.baseURL else { return }
        self.baseURL = baseURL
        cachedManifest = nil
    }

    func isConfigured() -> Bool { baseURL != nil }

    /// Oublie le manifeste mémorisé. Le prochain `manifest()` le relira.
    ///
    /// Réservé au rafraîchissement demandé par l'utilisateur : le reste du
    /// temps, relire le manifeste une fois par session est exactement ce qu'on
    /// veut — un client à jour n'a aucune raison de le redemander.
    func invalidateManifest() {
        cachedManifest = nil
    }

    func manifest() async throws -> ContentManifest {
        if let cachedManifest { return cachedManifest }
        guard let baseURL else { throw ContentCDNError.notConfigured }
        let manifest: ContentManifest = try await fetch(baseURL.appending(path: "content/manifest.json"))
        cachedManifest = manifest
        return manifest
    }

    /// Fragments d'une collection, dans l'ordre. Le chemin porte la version,
    /// donc chaque URL est immuable et peut être servie depuis le cache
    /// indéfiniment.
    func bundles<Item: ContentItem>(for collectionName: String) async throws -> [ContentBundle<Item>] {
        guard let baseURL else { throw ContentCDNError.notConfigured }
        let manifest = try await manifest()
        guard let info = manifest.collections[collectionName] else { return [] }

        var bundles: [ContentBundle<Item>] = []
        for chunk in 0..<info.chunks {
            let url = baseURL.appending(path: "content/v\(manifest.version)/\(collectionName)/\(chunk).json")
            do {
                bundles.append(try await fetch(url))
            } catch {
                // Décodage tolérant fragment par fragment, même politique que
                // `ChunkedContentRepository` : un fragment malformé ne doit pas
                // vider toute la collection.
                print("ContentCDN: fragment illisible \(url.lastPathComponent) — \(error)")
            }
        }
        return bundles
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        // Le code de statut n'est vérifié que s'il y en a un. Une réponse non
        // HTTP qui a rendu des données est valide — c'est le cas d'un `file://`,
        // ce dont les tests se servent pour exercer le vrai chemin de décodage
        // sans lancer de serveur.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentCDNError.badResponse(url: url)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum ContentCDNError: Error {
    case notConfigured
    case badResponse(url: URL)
}
