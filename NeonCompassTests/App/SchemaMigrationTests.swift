import Foundation
import SwiftData
import Testing
@testable import NeonCompass

/// L'entité retirée du schéma le 2026-08-19, redéclarée ICI et nulle part
/// ailleurs. Le nom de classe est ce dont SwiftData tire le nom d'entité, donc
/// cette déclaration reproduit à l'octet ce qu'une installation existante porte
/// dans son magasin — et la garder dans la cible de test est la seule façon
/// d'écrire un magasin « d'avant » sans réintroduire le modèle dans l'app.
@Model
final class TrophyProgress {
    @Attribute(.unique) var trophyID: String
    var updatedAt: Date = Date.now

    init(trophyID: String, updatedAt: Date = .now) {
        self.trophyID = trophyID
        self.updatedAt = updatedAt
    }
}

/// `NeonCompassApp` construit son `ModelContainer` en `try!` — un schéma qu'on
/// n'arrive pas à ouvrir n'est pas une erreur affichable, c'est un plantage au
/// lancement. Retirer une entité du schéma est donc le genre de changement
/// qu'on ne suppose pas : on le prouve.
struct SchemaMigrationTests {
    /// Le schéma des installations déjà déployées, au 2026-08-19.
    private static let before: [any PersistentModel.Type] = [
        FoundEntry.self, PersonalPin.self, FavoriteCheat.self,
        ContentCacheEntry.self, BlockedContributor.self, TrophyProgress.self,
    ]

    /// Celui que `NeonCompassApp.init()` ouvre désormais. Toute divergence entre
    /// cette liste et celle de l'app rend ce test menteur : il prouverait la
    /// compatibilité d'un schéma que personne n'ouvre.
    private static let after: [any PersistentModel.Type] = [
        FoundEntry.self, PersonalPin.self, FavoriteCheat.self,
        ContentCacheEntry.self, BlockedContributor.self,
    ]

    /// LE test du retrait des trophées. Un magasin écrit par le build d'avant
    /// porte la table `TROPHYPROGRESS` et ses lignes de métadonnées ; le build
    /// d'après ouvre ce même fichier avec un schéma qui ne la mentionne plus.
    ///
    /// La progression locale doit survivre au passage : c'est la seule chose que
    /// l'utilisateur perdrait, et il n'en existe aucune copie serveur pour le
    /// gratuit.
    @Test func aStoreWrittenWithTheTrophyEntityStillOpensWithoutIt() throws {
        let url = URL.temporaryDirectory.appending(path: "schema-drop-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
                )
            }
        }

        // 1. Le magasin d'avant, refermé avant la suite : un conteneur encore
        //    vivant garderait ses pages en WAL, et le second lirait un fichier
        //    que la vraie mise à jour ne verra jamais.
        do {
            let container = try ModelContainer(
                for: Schema(Self.before), configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            context.insert(TrophyProgress(trophyID: "trophy.legacy"))
            context.insert(FoundEntry(poiID: "poi-1"))
            try context.save()
            // La prémisse, et pas un détail : sans cette assertion le test
            // passerait tout aussi bien si l'entité n'avait jamais atteint le
            // fichier — donc s'il ne prouvait rien du tout.
            #expect(try context.fetch(FetchDescriptor<TrophyProgress>()).count == 1)
        }

        // 2. Le schéma d'après, sur le même fichier. `try` là où l'app fait
        //    `try!` : ici l'échec est un test rouge, en production c'est une app
        //    qui ne démarre pas.
        let container = try ModelContainer(
            for: Schema(Self.after), configurations: ModelConfiguration(url: url)
        )
        let found = try ModelContext(container).fetch(FetchDescriptor<FoundEntry>())
        #expect(found.map(\.poiID) == ["poi-1"])
    }

    /// Le corollaire : une entité de plus dans le fichier n'est pas la même
    /// chose qu'une entité de plus dans le schéma. Rouvrir avec l'ancien schéma
    /// après le passage au nouveau doit rester possible — c'est ce qui se passe
    /// quand l'utilisateur réinstalle la version précédente depuis TestFlight.
    @Test func theOldBuildCanStillOpenAStoreTouchedByTheNewOne() throws {
        let url = URL.temporaryDirectory.appending(path: "schema-back-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
                )
            }
        }

        do {
            let container = try ModelContainer(
                for: Schema(Self.after), configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(container)
            context.insert(FoundEntry(poiID: "poi-2"))
            try context.save()
        }

        let container = try ModelContainer(
            for: Schema(Self.before), configurations: ModelConfiguration(url: url)
        )
        let found = try ModelContext(container).fetch(FetchDescriptor<FoundEntry>())
        #expect(found.map(\.poiID) == ["poi-2"])
    }
}
