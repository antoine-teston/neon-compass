import Foundation

/// Manifeste du contenu servi par le CDN.
///
/// Il porte la carte des fragments ET leur version : **un client à jour lit ce
/// seul fichier et s'arrête là**. C'est le seul fichier en clair de
/// l'arborescence, et le seul court-caché — c'est aussi le seul qui bouge à
/// chaque publication.
struct ContentManifest: Decodable, Sendable {
    struct CollectionInfo: Decodable, Sendable {
        /// Version de CETTE collection, pas de la publication.
        ///
        /// Elle n'avance que si le contenu de la collection a changé. C'est ce
        /// qui fait qu'une publication d'actu ne déclenche plus le
        /// retéléchargement des POI — le portillon de version prétendait être
        /// un delta sans en être un.
        let version: Int
        let chunks: Int
        let count: Int
    }

    /// Version de la publication, pour répondre à « quel contenu est en ligne ».
    /// Le client ne la compare pas : il compare celle de sa collection.
    let version: Int
    let commit: String?
    let collections: [String: CollectionInfo]
}

/// Accès au contenu statique, sans SDK.
///
/// Le trafic de cette app est à 95 % de la lecture de contenu partagé et
/// versionné : une charge de distribution de fichiers, pas une charge de base.
/// Un JSON derrière une URL répond depuis le cache en périphérie et se lit
/// depuis n'importe quel langage — ce qui compte le jour où un second client
/// existe.
///
/// Le manifeste est relu une fois par session au plus : les deux consommateurs
/// (garde de version et dépôt de fragments) le partagent, donc une
/// synchronisation ne fait pas deux fois la même requête.
/// Manifeste des fragments de spots communautaires.
///
/// Séparé du manifeste éditorial parce que ses deux producteurs le sont : les
/// spots se reconstruisent au fil des approbations, le contenu éditorial se
/// publie à la main. Un fichier chacun, aucune course à la clé.
struct CommunityBundleManifest: Decodable, Sendable {
    let version: Int
    let chunks: Int
    let count: Int
}

actor ContentCDN {
    static let shared = ContentCDN()

    private var cachedManifest: ContentManifest?
    private var cachedCommunityManifest: CommunityBundleManifest?
    private var baseURL: URL?

    /// Configuré au lancement depuis `app_config`. Tant qu'il est nil, l'app
    /// vit sur le socle embarqué et son cache — et changer d'hébergeur ne
    /// demande jamais une mise à jour de l'app.
    func configure(baseURL: URL?) {
        guard baseURL != self.baseURL else { return }
        self.baseURL = baseURL
        cachedManifest = nil
        cachedCommunityManifest = nil
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
        let data = try await fetch(baseURL.appending(path: "content/manifest.json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: data)
        cachedManifest = manifest
        return manifest
    }

    /// Version d'une collection, ou zéro si le manifeste ne la connaît pas.
    ///
    /// Zéro et pas une erreur : une collection absente du manifeste n'a jamais
    /// été publiée, et `ContentStore` doit alors ne rien télécharger plutôt que
    /// d'aller chercher des fragments qui n'existent pas.
    func version(for collectionName: String) async throws -> Int {
        try await manifest().collections[collectionName]?.version ?? 0
    }

    /// Fragments d'une collection, dans l'ordre.
    ///
    /// Le chemin porte la version DE LA COLLECTION, donc chaque URL est
    /// immuable et peut être servie depuis le cache indéfiniment.
    func bundles<Item: ContentItem>(for collectionName: String) async throws -> [ContentBundle<Item>] {
        guard let baseURL else { throw ContentCDNError.notConfigured }
        let manifest = try await manifest()
        guard let info = manifest.collections[collectionName] else { return [] }

        var bundles: [ContentBundle<Item>] = []
        for chunk in 0..<info.chunks {
            let url = baseURL.appending(path: "content/v\(info.version)/\(collectionName)/\(chunk).json.z")
            do {
                let compressed = try await fetch(url)
                let data = try Self.inflate(compressed)
                bundles.append(try JSONDecoder().decode(ContentBundle<Item>.self, from: data))
            } catch {
                // Décodage tolérant fragment par fragment : un fragment
                // illisible — mal formé, tronqué, mal décompressé — ne doit pas
                // vider toute la collection.
                print("ContentCDN: fragment illisible \(url.lastPathComponent) — \(error)")
            }
        }
        return bundles
    }

    // MARK: - Spots communautaires

    func invalidateCommunityManifest() {
        cachedCommunityManifest = nil
    }

    func communityManifest() async throws -> CommunityBundleManifest {
        if let cachedCommunityManifest { return cachedCommunityManifest }
        guard let baseURL else { throw ContentCDNError.notConfigured }
        let path = "content/\(CommunityBundleVersionProvider.collectionName)/manifest.json"
        let data = try await fetch(baseURL.appending(path: path))
        let manifest = try JSONDecoder().decode(CommunityBundleManifest.self, from: data)
        cachedCommunityManifest = manifest
        return manifest
    }

    /// Zéro quand le manifeste est absent : aucune reconstruction n'a encore
    /// tourné. `ContentStore` ne déclenche alors aucun téléchargement — mieux
    /// vaut afficher le cache que d'aller lire des fragments inexistants.
    func communityVersion() async throws -> Int {
        (try? await communityManifest().version) ?? 0
    }

    func communityBundles<Item: ContentItem>() async throws -> [ContentBundle<Item>] {
        guard let baseURL else { throw ContentCDNError.notConfigured }
        let manifest = try await communityManifest()
        let collection = CommunityBundleVersionProvider.collectionName

        var bundles: [ContentBundle<Item>] = []
        for chunk in 0..<manifest.chunks {
            let url = baseURL.appending(path: "content/\(collection)/v\(manifest.version)/\(chunk).json.z")
            do {
                bundles.append(try JSONDecoder().decode(ContentBundle<Item>.self, from: Self.inflate(try await fetch(url))))
            } catch {
                print("ContentCDN: fragment communautaire illisible \(url.lastPathComponent) — \(error)")
            }
        }
        return bundles
    }

    /// DEFLATE brut (RFC 1951), sans en-tête zlib ni gzip.
    ///
    /// Les fragments sont pré-compressés à la publication parce que Supabase
    /// Storage ne compresse pas à la volée et ne permet pas non plus de poser
    /// `Content-Encoding` au téléversement (supabase-js#1883, demande ouverte) :
    /// la décompression transparente par `URLSession` est hors d'atteinte, donc
    /// elle se fait ici. Sans elle, ce sont 423 Ko qui sortent au lieu de 70, à
    /// chaque synchronisation complète et par utilisateur, sur un quota
    /// d'egress partagé avec la base et l'authentification.
    ///
    /// `.zlib` est le nom que le framework Compression donne au DEFLATE BRUT —
    /// pas au format zlib de la RFC 1950, malgré ce que le nom suggère. C'est
    /// exactement ce que produit `zlib.deflateRawSync` côté Node, sans en-tête
    /// à retirer de part et d'autre. Un test à partir d'une fixture produite par
    /// Node fige cet accord, qui vit des deux côtés d'une frontière réseau.
    static func inflate(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .zlib) as Data
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        // Le code de statut n'est vérifié que s'il y en a un. Une réponse non
        // HTTP qui a rendu des données est valide — c'est le cas d'un `file://`,
        // ce dont les tests se servent pour exercer le vrai chemin de décodage
        // sans lancer de serveur.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentCDNError.badResponse(url: url)
        }
        return data
    }
}

enum ContentCDNError: Error {
    case notConfigured
    case badResponse(url: URL)
}
