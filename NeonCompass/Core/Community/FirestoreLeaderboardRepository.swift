import FirebaseFirestore

/// Lit le document unique écrit par `rebuildLeaderboard`. Une seule lecture par
/// ouverture d'onglet, quel que soit le nombre d'utilisateurs — jamais une
/// requête sur la collection des profils.
final class FirestoreLeaderboardRepository: LeaderboardRepository {
    nonisolated(unsafe) private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func fetchWeekly() async throws -> Leaderboard? {
        let document = try await firestore.collection("leaderboards").document("weekly").getDocument()
        guard document.exists else { return nil }
        return try document.data(as: Leaderboard.self)
    }
}
