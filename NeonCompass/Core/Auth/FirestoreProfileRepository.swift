import FirebaseFirestore

/// Implémentation réelle de ProfileRepository. Le document peut ne pas
/// encore exister juste après le sign-in (la Cloud Function createUserProfile
/// tourne de façon asynchrone sur l'événement de création du user Auth) —
/// retourner nil dans ce cas plutôt que de faire échouer l'appelant.
final class FirestoreProfileRepository: ProfileRepository {
    nonisolated(unsafe) private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func fetchProfile(uid: String) async throws -> Profile? {
        let document = try await firestore.collection("profiles").document(uid).getDocument()
        guard document.exists else { return nil }
        return try document.data(as: Profile.self)
    }
}
