import FirebaseFirestore

/// Version des fragments de spots communautaires, lue dans un document unique.
///
/// Pourquoi pas Remote Config, comme le contenu éditorial : les spots changent
/// au fil des approbations, pas au rythme des publications. Réutiliser
/// `contentVersion` ferait re-synchroniser le contenu à chaque approbation et
/// l'inverse ; et publier un template Remote Config toutes les cinq minutes
/// depuis une Function est limité en débit.
///
/// **C'est ce document qui rend le lancement gratuit** : un client à jour lit
/// ce seul document et s'arrête là. Une lecture, contre toute la collection
/// `contributions` auparavant.
///
/// Il vit dans `content_bundles`, déjà en lecture publique — aucune règle
/// Firestore à ajouter.
struct CommunityBundleVersionProvider: ContentVersionProviding {
    /// Écrit par `rebuildCommunityBundles` (voir
    /// `functions/src/communityBundles.ts`, `MANIFEST_ID`).
    static let manifestPath = "content_bundles/community_spots_manifest"

    /// Valeur du champ `collection` des fragments, et clé du cache SwiftData.
    /// Doit rester identique à `BUNDLE_COLLECTION` côté Function — la valeur est
    /// dupliquée des deux côtés d'une frontière réseau, un test la fige.
    static let collectionName = "community_spots"

    private let document: DocumentReference

    init(firestore: Firestore = Firestore.firestore()) {
        document = firestore.document(Self.manifestPath)
    }

    func currentVersion() async throws -> Int {
        let snapshot = try await document.getDocument()
        // Manifeste absent = aucune reconstruction n'a encore tourné. Version 0,
        // donc `ContentStore` ne déclenche aucun téléchargement : mieux vaut
        // afficher le cache (ou rien) que de lire des fragments inexistants.
        return snapshot.get("version") as? Int ?? 0
    }
}
