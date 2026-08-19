import Foundation

/// Ce que la carte Découverte affiche pour un jeu, dérivé sans SwiftUI.
///
/// Existe pour la même raison que `ProfileHeaderState` : la règle « un tiret,
/// jamais 0 % » et la règle « le compte vient des POI du jeu, pas de ses défis »
/// sont toutes deux invisibles dans une vue, et toutes deux fausses par défaut
/// si personne ne les teste.
struct DiscoveryGameState: Equatable, Identifiable {
    let game: Game
    /// `nil` tant qu'aucun défi du jeu n'a de total connu. La vue trace alors un
    /// tiret et pas un arc — 0 % dirait « tu n'as rien trouvé » là où la vérité
    /// est « on ne sait pas encore combien il y en a ».
    let progress: Double?
    /// Lieux cochés du jeu, comptés sur ses POI.
    let foundCount: Int
    /// Total attendu, agrégé sur les défis qui en ont un. `nil` quand aucun n'en
    /// a — auquel cas la vue n'affiche que le compte absolu.
    let expectedCount: Int?

    var id: String { game.rawValue }
}

struct DiscoveryState: Equatable {
    /// **Les deux jeux, toujours, dans l'ordre de `Game`.**
    ///
    /// C'est la suppression du filtre `gamesWithChallenges` qui fait apparaître
    /// le volet à venir : les quinze collections publiées sont toutes celles de
    /// la carte de référence, donc filtrer sur « a au moins un défi » le rendait
    /// invisible dans l'écran censé montrer sa progression.
    ///
    /// L'ordre est celui de `GameSwitch` — le jeu à venir d'abord — pour la
    /// raison que `GameSwitch` documente déjà : deux contrôles dont l'ordre
    /// diffèrerait seraient pires que n'importe lequel des deux ordres.
    let games: [DiscoveryGameState]
    let challengeCount: Int

    init(challenges: [ChallengeProgress], foundCountByGame: [Game: Int]) {
        games = Game.allCases.map { game in
            let ofGame = challenges.filter { $0.collection.game == game }
            let expected = ofGame.compactMap(\.expected).reduce(0, +)
            return DiscoveryGameState(
                game: game,
                progress: ChallengeProgressCalculator.overall(ofGame),
                foundCount: foundCountByGame[game] ?? 0,
                expectedCount: expected > 0 ? expected : nil
            )
        }
        challengeCount = challenges.count
    }
}
