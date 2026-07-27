import Foundation

/// Avancement d'un joueur sur une collection.
struct ChallengeProgress: Identifiable, Equatable, Sendable {
    let collection: POICollection
    /// POI trouvés, **borné par `expectedCount`** : un jeu de données plus riche
    /// que le total attendu ne doit pas produire « 52 / 50 ».
    let found: Int
    /// POI que nous référençons réellement pour cette collection. Comparé à
    /// `expectedCount`, il dit si le trou est chez le joueur ou chez nous.
    let referenced: Int

    var id: String { collection.id }
    var expected: Int? { collection.expectedCount }

    /// `nil` quand le total attendu est inconnu : l'UI affiche alors un
    /// décompte brut plutôt qu'un pourcentage inventé.
    var fraction: Double? {
        guard let expected, expected > 0 else { return nil }
        return Double(found) / Double(expected)
    }

    /// Vrai quand nos données sont en retard sur le jeu — utile à afficher,
    /// parce que sinon un joueur qui a tout trouvé sur nos 47 POI se demande
    /// pourquoi il plafonne à 47/50.
    var isDataIncomplete: Bool {
        guard let expected else { return false }
        return referenced < expected
    }
}

/// Calcul pur de l'avancement, sans SwiftData ni Firestore.
///
/// Isolé de `ProgressionModel` pour deux raisons : il se teste seul, et il doit
/// être appelé **une fois par changement** de `(pois, foundIDs)` plutôt qu'à
/// chaque lecture. L'implémentation précédente refiltrait tout le tableau à
/// chaque accès, et l'écran de progression lisait sept propriétés calculées par
/// rendu — sept balayages complets, redéclenchés à chaque changement
/// d'observation.
enum ChallengeProgressCalculator {
    /// - Parameter foundIDs: identifiants cochés par le joueur. Ceux qui ne
    ///   correspondent à aucun POI connu sont ignorés : un POI supprimé en amont
    ///   laisse derrière lui un `FoundEntry` orphelin qui, sans ça, gonflerait
    ///   le décompte au-delà du réel.
    static func challenges(
        collections: [POICollection],
        pois: [POI],
        foundIDs: Set<String>
    ) -> [ChallengeProgress] {
        var referenced: [String: Int] = [:]
        var found: [String: Int] = [:]

        for poi in pois {
            guard let collection = poi.collection else { continue }
            // Un POI fusionné n'est plus une entrée à part entière : il ne compte
            // pas dans le dénominateur, seulement comme alias vers sa cible.
            guard poi.mergedInto == nil else { continue }
            referenced[collection, default: 0] += 1
        }

        // Les alias sont résolus d'abord : cocher un doublon avant sa fusion doit
        // continuer de compter, sinon la fusion effacerait la progression de tous
        // ceux qui l'avaient trouvé.
        let aliases = Dictionary(
            pois.compactMap { poi in poi.mergedInto.map { (poi.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let resolvedFoundIDs = Set(foundIDs.map { aliases[$0] ?? $0 })

        for poi in pois where resolvedFoundIDs.contains(poi.id) {
            guard let collection = poi.collection, poi.mergedInto == nil else { continue }
            found[collection, default: 0] += 1
        }

        return collections
            .filter(\.isChallenge)
            .map { collection in
                let rawFound = found[collection.id] ?? 0
                return ChallengeProgress(
                    collection: collection,
                    found: collection.expectedCount.map { min(rawFound, $0) } ?? rawFound,
                    referenced: referenced[collection.id] ?? 0
                )
            }
    }

    /// Avancement global d'un jeu : somme des trouvés sur somme des totaux
    /// attendus.
    ///
    /// Seules les collections à total **connu** entrent dans le calcul. Renvoie
    /// `nil` quand aucune ne l'est — afficher 0 % serait faux, alors qu'on ne
    /// sait simplement pas encore. C'est l'état de GTA VI au lancement.
    static func overall(_ challenges: [ChallengeProgress]) -> Double? {
        let counted = challenges.filter { $0.expected != nil }
        let expected = counted.reduce(0) { $0 + ($1.expected ?? 0) }
        guard expected > 0 else { return nil }
        return Double(counted.reduce(0) { $0 + $1.found }) / Double(expected)
    }
}
