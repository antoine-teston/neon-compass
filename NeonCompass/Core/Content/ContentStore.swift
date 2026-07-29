import Foundation
import Observation
import SwiftData

/// Store générique offline-first pour un type de contenu Firestore, fusionnant
/// un socle embarqué avec un overlay distant (voir `ContentMerge`).
/// Remplace les trois implémentations dupliquées
/// (POIContentStore/CheatContentStore/GuideContentStore) — identiques à un
/// renommage de type près. `collectionName` est maintenant un paramètre
/// d'instance (au lieu d'une constante statique par type) puisqu'un seul
/// type générique sert toutes les collections.
@Observable
@MainActor
final class ContentStore<Item: ContentItem> {
    private let collectionName: String

    /// Entrées embarquées dans le binaire. Disponibles au premier lancement,
    /// sans réseau ni lecture facturée. Vide pour les collections purement
    /// distantes (cheats, guides, actu, trophées).
    private let seed: [Item]

    /// Socle fusionné avec l'overlay — c'est ce que lisent les features.
    private(set) var items: [Item]

    private let remote: any ContentRemoteRepository<Item>
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(
        collectionName: String,
        seed: [Item] = [],
        remote: any ContentRemoteRepository<Item>,
        versionProvider: ContentVersionProviding,
        modelContext: ModelContext
    ) {
        self.collectionName = collectionName
        self.seed = seed
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.items = ContentMerge.merge(
            seed: seed,
            overlay: Self.loadCached(collectionName: collectionName, from: modelContext)
        )
    }

    func syncIfNeeded() async throws {
        try await sync(force: false)
    }

    /// Synchronisation demandée explicitement par l'utilisateur — un tirer-pour-
    /// rafraîchir. Contourne la garde de version, et **invalide d'abord ce que
    /// le fournisseur de version garde en cache**.
    ///
    /// Ce second point est ce qui fait la différence entre un geste qui marche
    /// et une animation décorative : `ContentCDN` mémorise le manifeste pour
    /// toute la session, puisqu'un client à jour n'a aucune raison de le relire.
    /// Sans invalidation, rafraîchir relirait la version d'il y a une heure,
    /// conclurait « rien de neuf », et ne verrait jamais une publication faite
    /// entre-temps — exactement le cas où l'on tire sur l'écran.
    func refresh() async throws {
        await versionProvider.invalidate()
        try await sync(force: true)
    }

    private func sync(force: Bool) async throws {
        let remoteVersion = try await versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(collectionName: collectionName, from: modelContext)
        // Cette garde est ce qui rend le lancement gratuit : sans nouvelle
        // version, aucun fragment n'est téléchargé.
        //
        // Elle suppose que `remoteVersion` est une VRAIE version, jamais un
        // « je ne sais pas encore ». C'est le rôle de
        // `ContentSourceConfigurator.ready()`, attendu par les fournisseurs de
        // version : sans lui, Remote Config pas encore activé rendait 0, la
        // garde lisait « à jour », et la collection restait vide pour toute la
        // session — sans erreur. Ne pas affaiblir cette garde pour compenser :
        // c'est en amont que la version doit être digne de foi.
        //
        // `force` ne l'affaiblit pas non plus : il ne s'active que sur un geste
        // explicite de l'utilisateur, qui a le droit d'exiger une lecture même
        // si rien ne semble avoir bougé.
        guard force || remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        // On met en cache l'OVERLAY, pas le résultat fusionné. Sinon une mise à
        // jour de l'app livrant un socle enrichi serait masquée par un cache
        // écrit à l'époque de l'ancien socle, jusqu'au prochain bump de version.
        let data = try JSONEncoder().encode(fetched)

        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(ContentCacheEntry(collectionName: name, json: data, version: remoteVersion))
        }
        try modelContext.save()

        items = ContentMerge.merge(seed: seed, overlay: fetched)
    }

    private static func loadCached(collectionName: String, from modelContext: ModelContext) -> [Item] {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([Item].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(collectionName: String, from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<ContentCacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
