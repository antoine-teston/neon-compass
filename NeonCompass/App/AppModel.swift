import Observation

@Observable
@MainActor
final class AppModel {
    var selectedTab: AppTab = .feed

    /// La feuille de réglages, ouverte depuis la molette de la barre haute.
    ///
    /// Ici et non dans un écran : la molette est présente sur quatre onglets, et
    /// l'invitation à se connecter du Profil l'ouvre elle aussi. Un `@State`
    /// d'écran ne pourrait servir que l'un des deux.
    var showsSettings = false

    /// La carte réclamée par une navigation venue d'un autre onglet.
    ///
    /// **Pourquoi ce détour plutôt qu'un simple changement d'onglet.**
    /// `MapScreen.mapGame` est un `@State` qui vaut `.reference` — V — à chaque
    /// lancement, et ne persiste rien. Or « Proposer un lieu » n'apparaît que
    /// sur VI. Les deux invitations à contribuer, la ligne du profil et le CTA
    /// du volet Propositions, envoyaient donc sur une carte où le geste qu'elles
    /// venaient d'enseigner ne mène nulle part : l'appui long ouvre bien son
    /// menu, sans l'option. Constaté au simulateur le 2026-08-06, et **à tous
    /// les coups** — ce n'était pas un cas de bord, c'était le seul cas.
    private(set) var requestedMapGame: Game?

    func openMapToContribute() {
        requestedMapGame = .leonida
        selectedTab = .map
    }

    /// Rend la demande en cours et l'efface aussitôt.
    ///
    /// Une seule consommation : sans quoi une bascule manuelle vers V, juste
    /// après, serait défaite au prochain rendu de `MapScreen`.
    func consumeRequestedMapGame() -> Game? {
        defer { requestedMapGame = nil }
        return requestedMapGame
    }
}
