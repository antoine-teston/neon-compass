import Foundation

/// Une ligne du classement public. Aucune donnée personnelle : le handle est
/// généré par nous, jamais saisi — c'est ce qui rend ce classement affichable
/// sans une seule ligne de modération.
struct LeaderboardRow: Codable, Equatable, Identifiable, Sendable {
    let uid: String
    let handle: String
    let xp: Int
    let approvedCount: Int

    var id: String { uid }
}

/// Le document unique `leaderboards/weekly`, écrit par la Function planifiée.
struct Leaderboard: Codable, Equatable, Sendable {
    let rows: [LeaderboardRow]
}

protocol LeaderboardRepository: Sendable {
    func fetchWeekly() async throws -> Leaderboard?
}
