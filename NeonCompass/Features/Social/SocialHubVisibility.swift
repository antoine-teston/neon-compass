import Foundation

/// Quelles sections du hub existent. Type pur : la règle « une section sans
/// contenu disparaît » (la règle `showsGamePicker`, généralisée) se teste ici,
/// pas à l'écran.
struct SocialHubVisibility: Equatable {
    let showsVoteModule: Bool
    let showsLeaderboardTile: Bool
    let showsBanner: Bool

    init(
        serverEnabled: Bool,
        proposalCount: Int,
        leaderboardRowCount: Int,
        heroShowsEvent: Bool,
        isProEntitled: Bool
    ) {
        showsVoteModule = serverEnabled && proposalCount > 0
        showsLeaderboardTile = serverEnabled && leaderboardRowCount > 0
        // La règle existante de l'écran, reprise telle quelle : du contenu
        // affiché, et pas d'abonné Pro. Un état vide n'est pas un écran de liste.
        showsBanner = heroShowsEvent && !isProEntitled
    }

    /// La pastille du module « À voter » : ce que JE n'ai pas encore voté.
    /// Sur des identifiants et non des `Contribution` : c'est ce qui rend le
    /// calcul testable sans fixture.
    static func unvotedCount(spotIDs: [String], votedIDs: Set<String>) -> Int {
        spotIDs.filter { !votedIDs.contains($0) }.count
    }
}
