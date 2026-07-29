import Foundation
import SwiftData

/// Cache SwiftData d'une collection de contenu entière, sérialisée en JSON.
/// Un seul type de modèle partagé entre tous les types de contenu
/// (POI, Cheat, Guide, ...), une ligne par `collectionName` — remplace les
/// trois `CacheEntry` dupliqués (POI/Cheat/Guide) qui ne différaient que
/// par leur nom de type.
/// v1 : granularité "toute la collection" (pas de delta par document) —
/// suffisant tant que le volume de contenu reste modeste (spec §7 : le
/// pipeline de contenu vise des dizaines à quelques centaines d'entrées).
@Model
final class ContentCacheEntry {
    @Attribute(.unique) var collectionName: String
    var json: Data
    var version: Int

    /// Build de l'app qui a écrit ce cache.
    ///
    /// Ce que ce cache contient n'est PAS la charge reçue du réseau : c'est le
    /// modèle Swift ré-encodé (`JSONEncoder().encode(fetched)`). Il est donc
    /// amputé de tout champ que le build de l'époque ne connaissait pas encore.
    ///
    /// D'où le bug qu'on a mis du temps à voir : ajouter un champ au modèle le
    /// laissait invisible chez les utilisateurs existants, parce que la garde de
    /// version voyait un contenu « à jour » et ne re-téléchargeait pas. Il aurait
    /// fallu attendre la prochaine publication de contenu pour qu'un champ livré
    /// par une mise à jour d'app apparaisse — silencieusement, sans erreur.
    ///
    /// Un cache écrit par un autre build est donc considéré comme absent. Ça
    /// coûte une lecture par collection à la première ouverture après une mise à
    /// jour, ce qui est très exactement le moment où on l'accepte volontiers.
    /// Optionnel, et c'est délibéré : un attribut non optionnel ajouté à un
    /// `@Model` déjà déployé fait échouer la migration légère de SwiftData. `nil`
    /// désigne exactement ce qu'on veut désigner — un cache écrit avant que
    /// l'app ne sache d'où venaient ses caches — et il est traité comme périmé.
    var appBuild: String?

    init(collectionName: String, json: Data, version: Int, appBuild: String? = ContentCacheEntry.currentAppBuild) {
        self.collectionName = collectionName
        self.json = json
        self.version = version
        self.appBuild = appBuild
    }

    /// Version ET build : deux apps de même version marketing mais de builds
    /// différents ont pu changer un modèle entre deux passages en TestFlight.
    static var currentAppBuild: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short)+\(build)"
    }
}
