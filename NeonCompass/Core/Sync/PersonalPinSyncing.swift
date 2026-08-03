import Foundation

/// Une épingle telle qu'elle voyage.
///
/// Volontairement plate et sans référence au modèle SwiftData : `PersonalPin`
/// est une classe liée à un `ModelContext`, donc ni `Sendable` ni transportable
/// hors du fil principal. L'instantané se prend sur le `@MainActor`, et c'est
/// lui qui franchit la frontière.
struct PersonalPinSyncItem: Sendable, Equatable {
    let id: UUID
    let game: String
    let x: Double
    let y: Double
    let title: String
    let note: String
    let icon: String
    let isDone: Bool
    let createdAt: Date
    let updatedAt: Date
    /// Non nul = pierre tombale. L'épingle a été supprimée sur un appareil, et
    /// cette information doit voyager comme le reste : un `delete` qui ne
    /// laisserait rien derrière lui ne se propagerait jamais, et l'autre
    /// appareil ressusciterait l'épingle qu'il possède encore.
    let deletedAt: Date?
}

/// Abstraction du miroir distant du carnet.
///
/// La synchro est Pro + connecté (spec : « nécessite le compte »), et ce
/// protocole n'en a aucun avis — comme `ProgressionSyncing`, il déplace des
/// données quand on le lui demande. C'est à ses appelants de vérifier
/// `ProEntitlementModel.isProEntitled` ET `AuthModel.userID` avant de
/// l'appeler.
protocol PersonalPinSyncing: Sendable {
    func upload(_ item: PersonalPinSyncItem) async
    func fetchAll(uid: String) async -> [PersonalPinSyncItem]
}
