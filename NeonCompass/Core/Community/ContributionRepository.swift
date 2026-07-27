import Foundation

/// `fetchApproved` a disparu de ce protocole : les spots approuvés passent
/// désormais par `ContentStore<Contribution>` et les fragments de
/// `content_bundles`, pas par une lecture directe de la collection.
///
/// `fetchMine` reste une requête directe, délibérément : elle ne renvoie que
/// les quelques contributions d'un seul utilisateur, et elle doit être fraîche —
/// un contributeur doit voir sa soumission tout de suite, sans attendre la
/// prochaine reconstruction des fragments.
protocol ContributionRepository: Sendable {
    func fetchMine(uid: String) async throws -> [Contribution]
}
