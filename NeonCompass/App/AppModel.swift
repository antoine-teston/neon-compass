import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    private static let gameKey = "cheatsActiveGame"

    var selectedTab: AppTab = .feed

    /// Le jeu regardé sur l'écran Codes.
    ///
    /// Ici et non dans `CheatsModel`, où il vivait : la bascule est passée dans
    /// la barre haute, que `RootView` monte AU-DESSUS de l'écran. L'état doit
    /// donc être visible des deux côtés, et le modèle de l'écran le reçoit au
    /// lieu de le détenir.
    ///
    /// La clé de persistance garde son ancien nom, `cheatsActiveGame`, qui ne
    /// décrit plus où l'état vit. La renommer renverrait au défaut tous ceux qui
    /// avaient déjà choisi — un nom exact ne vaut pas ce prix.
    ///
    /// `.reference` par défaut : c'est le jeu qui a des codes. Ouvrir sur celui
    /// qui n'en a pas encore afficherait un écran d'attente au premier lancement.
    var activeGame: Game {
        didSet { defaults.set(activeGame.rawValue, forKey: Self.gameKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeGame = defaults.string(forKey: Self.gameKey)
            .flatMap(Game.init(rawValue:)) ?? .reference
    }

    /// La feuille de réglages, ouverte depuis la molette de la barre haute.
    ///
    /// Ici et non dans un écran : la molette est présente sur quatre onglets, et
    /// l'invitation à se connecter du Profil l'ouvre elle aussi. Un `@State`
    /// d'écran ne pourrait servir que l'un des deux.
    var showsSettings = false

    /// La feuille de connexion, ouverte depuis un écran d'ONGLET.
    ///
    /// Distincte de `showsSettings` : se connecter n'est pas régler quelque
    /// chose, et l'invitation du Profil doit pouvoir l'ouvrir sans passer par
    /// les réglages.
    ///
    /// **Cette porte ne sert qu'aux appelants qui ne sont pas déjà dans une
    /// feuille.** `RootView` n'en présente qu'UNE à la fois : mesuré au
    /// simulateur le 2026-08-19, une demande faite pendant que les réglages sont
    /// à l'écran ne montre rien du tout, et attend en silence que la première se
    /// referme. Les appelants qui vivent déjà dans une feuille — l'appel des
    /// réglages déconnectés, l'alerte de contribution quand `ProposalsSheet` la
    /// porte — présentent donc `SignInSheet` eux-mêmes.
    var showsSignIn = false

    /// Le point de nouveauté de l'onglet Social : une semaine synchronisée que
    /// l'utilisateur n'a pas encore vue. Calculé par `RootView` au lancement,
    /// éteint à l'ouverture de l'onglet.
    var socialTabShowsDot = false

    /// L'identifiant de la semaine que le hub montrerait — ce que l'ouverture
    /// de l'onglet marque comme vu.
    var socialCurrentWeekID: String?

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
