import Foundation
import Observation
import SwiftData

/// Ce que l'utilisateur a trouvé — une seule fois pour toute l'app.
///
/// **Le défaut qu'il corrige.** `MapModel` et `ProgressionModel` tenaient chacun
/// son propre `Set<String>` au-dessus des mêmes `FoundEntry`, sans aucun canal
/// entre eux. Deux caches d'une seule vérité, donc une divergence garantie dès
/// que l'un écrit — et sur iPhone elle ne se refermait jamais :
/// `ProgressionSection` ne relisait son état que dans `.onAppear`, or
/// `RootView.compactLayout` garde les onglets visités MONTÉS dans un `ZStack` et
/// ne joue que sur l'opacité (c'est délibéré, cf. son commentaire : c'est ce qui
/// préserve le zoom, la recherche et la position de défilement). Changer
/// d'opacité ne redéclenche pas `.onAppear`. Cocher vingt lieux sur la carte
/// laissait donc l'anneau de progression, les compteurs de défis ET le résumé du
/// widget sur la photographie prise à la première visite du Profil, jusqu'au
/// prochain lancement de l'app.
///
/// Un simple compteur de révision partagé aurait suffi à réveiller l'écran, mais
/// aurait laissé les deux caches en place — c'est-à-dire le défaut. Ici il n'y en
/// a plus qu'un, et les deux modèles le lisent.
///
/// **Ce qu'il ne fait pas.** Il ne connaît pas la synchronisation distante :
/// `MapModel` reste responsable de téléverser ce qu'il vient d'écrire, parce que
/// c'est lui qui sait si l'utilisateur y a droit (Pro + compte). Le magasin ne
/// s'occupe que du disque local et du cache en mémoire.
///
/// `@MainActor` : un `ModelContext` de la fenêtre principale, lu par des corps de
/// vues.
@Observable
@MainActor
final class FoundStore {
    /// Identifiants des POI marqués « trouvé ». Lu directement par les corps de
    /// vues, donc jamais recalculé à la lecture — c'est tout l'intérêt du cache,
    /// et la raison pour laquelle les deux modèles en avaient chacun un.
    private(set) var foundIDs: Set<String> = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    /// Relit le disque.
    ///
    /// Redondant quand tout passe par ce magasin — et c'est précisément pourquoi
    /// il reste : tout ne passe pas par lui. Le chemin d'amorçage du widget
    /// construit un `ProgressionModel` jetable au lancement, et les tests
    /// insèrent des `FoundEntry` directement dans le contexte. Sans relecture,
    /// ces écritures « par derrière » resteraient invisibles.
    func refresh() {
        foundIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
    }

    func isFound(_ poiID: String) -> Bool {
        foundIDs.contains(poiID)
    }

    /// Bascule l'état d'un POI et le persiste. Renvoie le nouvel état, pour que
    /// l'appelant sache quoi téléverser sans relire.
    @discardableResult
    func toggle(_ poiID: String, at date: Date) -> Bool {
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            foundIDs.remove(poiID)
            try? modelContext.save()
            return false
        }
        modelContext.insert(FoundEntry(poiID: poiID, updatedAt: date))
        foundIDs.insert(poiID)
        try? modelContext.save()
        return true
    }

    /// Réconciliation dernière-écriture-gagne, élément par élément, de la
    /// progression distante vers le disque local.
    ///
    /// Vit ici et non plus dans `MapModel` : c'est le même magasin qui décide, et
    /// une réconciliation qui n'aurait mis à jour qu'un des deux caches aurait
    /// rouvert exactement la divergence que ce type ferme. Les trophées ne
    /// passent pas par là — ils ont leur propre entité, et `ProgressionModel` en
    /// reste le seul propriétaire.
    func reconcile(with remoteItems: [ProgressionSyncItem]) {
        for item in remoteItems where item.kind == .poi {
            let poiID = item.itemID
            let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing, existing.updatedAt >= item.updatedAt {
                continue // le local est au moins aussi récent, il gagne
            }

            if item.found {
                if let existing {
                    existing.updatedAt = item.updatedAt
                } else {
                    modelContext.insert(FoundEntry(poiID: poiID, foundAt: item.updatedAt, updatedAt: item.updatedAt))
                }
                foundIDs.insert(poiID)
            } else if let existing {
                modelContext.delete(existing)
                foundIDs.remove(poiID)
            }
        }
        try? modelContext.save()
    }
}
