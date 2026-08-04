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

    /// Mes votes, indexés par identifiant de contribution.
    ///
    /// Requête directe et non un fragment, pour la même raison que `fetchMine` :
    /// elle est personnelle et doit être fraîche. La politique
    /// `votes_select_own` l'autorise (`20260802120100_rls_policies.sql:95-97`)
    /// et l'index `votes_uid_idx` la sert.
    ///
    /// Elle porte deux usages d'un coup : découper le volet Propositions en deux
    /// sections, et donner au vote un état visible — jusqu'ici rien ne
    /// distinguait « je n'ai pas voté » de « j'ai voté pour ».
    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection]
}
