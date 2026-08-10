import ActivityKit
import Foundation

/// Démarrer, mettre à jour et arrêter la Live Activity des favoris.
///
/// Derrière un protocole parce que `ActivityKit` est un service système : les
/// écrans en dépendent, et un test ne peut pas en démarrer une. Même motif que
/// Supabase ou StoreKit dans ce projet.
@MainActor
protocol FavoritesLiveActivityControlling: AnyObject {
    /// Une activité des favoris tourne-t-elle en ce moment ?
    var isRunning: Bool { get }

    /// Le système autorise-t-il les activités ? Faux si l'utilisateur les a
    /// refusées dans Réglages — auquel cas le bouton doit le dire plutôt que de
    /// ne rien faire.
    var isAvailable: Bool { get }

    func start(game: String, state: FavoritesActivityAttributes.ContentState)

    /// Ne fait rien si aucune activité ne tourne : mettre à jour est le geste
    /// courant — chaque étoile posée, chaque changement de mode — et l'appelant
    /// n'a pas à savoir s'il y a quelque chose à mettre à jour.
    ///
    /// `async` et non un `Task` interne, et ce n'est pas un choix de style : sous
    /// concurrence stricte, capturer l'`Activity` dans une fermeture `@Sendable`
    /// est un ENVOI, que le compilateur refuse — le type n'est pas `Sendable`.
    /// Une méthode asynchrone isolée n'a pas de fermeture, donc pas d'envoi.
    func update(_ state: FavoritesActivityAttributes.ContentState) async
    func stop() async
}

@MainActor
@Observable
final class FavoritesLiveActivityController: FavoritesLiveActivityControlling {
    /// L'état observable, et RIEN de plus.
    ///
    /// L'`Activity` elle-même n'est pas retenue ici, et c'est ce qui rend ce
    /// fichier compilable sous concurrence stricte : `Activity` est une classe
    /// NON-`Sendable` dont `update` et `end` sont `nonisolated async`. La retenir
    /// sur l'acteur principal puis l'attendre revient à l'envoyer hors de son
    /// domaine — ce que Swift 6 refuse, à raison.
    ///
    /// Les deux méthodes qui l'attendent sont donc `nonisolated` et la retrouvent
    /// elles-mêmes : créée et consommée du même côté, elle ne traverse rien.
    /// ActivityKit s'y prête, `activities` étant sa façon prévue de retrouver ce
    /// qui tourne — c'est aussi ce qui permet de reprendre la main sur une
    /// activité survivant à la fermeture de l'app.
    private(set) var isRunning: Bool

    init() {
        isRunning = !Activity<FavoritesActivityAttributes>.activities.isEmpty
    }

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(game: String, state: FavoritesActivityAttributes.ContentState) {
        guard isAvailable, !isRunning else { return }
        let requested = try? Activity.request(
            attributes: FavoritesActivityAttributes(gameLabel: game),
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        isRunning = requested != nil
    }

    nonisolated func update(_ state: FavoritesActivityAttributes.ContentState) async {
        guard let activity = Activity<FavoritesActivityAttributes>.activities.first else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    nonisolated func stop() async {
        // Le drapeau tombe D'ABORD : un second appui ne doit pas relancer
        // l'arrêt d'une activité déjà en train de se retirer.
        await MainActor.run { self.isRunning = false }
        guard let activity = Activity<FavoritesActivityAttributes>.activities.first else { return }
        // `.immediate` : l'utilisateur vient de demander qu'elle disparaisse, la
        // laisser s'attarder à l'écran verrouillé serait lu comme une panne.
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
