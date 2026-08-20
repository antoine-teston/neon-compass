import Foundation
import Observation
import UIKit

/// `UserDefaults`-backed state for the theme and alternate app icon selection.
/// Constructed exactly once at `RootView` and injected via
/// `.environment(themeStore)`, same as `AuthModel`/`ProEntitlementModel` —
/// never a second per-screen instance. `RootView` applies l'accent du thème
/// EFFECTIF comme `.tint(...)` de toute l'app, ce qui rend le choix visible
/// partout au lieu d'être une préférence que personne ne lit.
@Observable
@MainActor
final class ThemeStore {
    private static let themeKey = "selectedTheme"
    private let defaults: UserDefaults

    private(set) var selectedTheme: NCTheme

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.themeKey).flatMap(NCTheme.init(rawValue:))
        self.selectedTheme = stored ?? .classic
    }

    func selectTheme(_ theme: NCTheme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: Self.themeKey)
    }

    /// Le thème RÉELLEMENT appliqué, une fois l'abonnement pris en compte.
    ///
    /// `SettingsScreen` masque déjà toute la section Apparence à qui n'est pas
    /// Pro, donc un utilisateur gratuit ne peut pas CHOISIR un thème payant.
    /// Mais il peut en avoir un : celui qui s'abonne, choisit `sunsetOverdrive`,
    /// puis laisse expirer son abonnement garde la valeur en `UserDefaults`, et
    /// le sélecteur disparaît sans que rien ne reprenne l'habillage. Le trou
    /// n'est pas dans le sélecteur, il est à la lecture — c'est donc ici qu'on
    /// le ferme.
    ///
    /// **On ne réécrit surtout pas la préférence stockée.** La dégrader sur
    /// place effacerait un choix que l'utilisateur a payé, et un
    /// réabonnement le ferait repartir de `classic` sans raison
    /// compréhensible. Une fonction pure laisse le choix intact et le rend dès
    /// que le droit revient.
    ///
    /// L'entitlement est un paramètre et non une dépendance : `ThemeStore`
    /// n'a ainsi rien à savoir de `ProEntitlementModel`, et cette règle se teste
    /// sans StoreKit.
    func effectiveTheme(isProEntitled: Bool) -> NCTheme {
        guard selectedTheme.isPro, !isProEntitled else { return selectedTheme }
        return .classic
    }

    /// Sets the alternate app icon by asset-catalog icon-set name (or `nil`
    /// to revert to the primary icon). No-ops on devices/simulators that
    /// don't support alternate icons.
    ///
    /// NOTE : le catalogue d'assets existe depuis le 2026-08-19 et porte
    /// l'`AppIcon` primaire, mais AUCUNE icône alternée n'y est encore déclarée
    /// — passer un nom ici échoue donc toujours en silence, côté UIKit, via le
    /// bloc de complétion. Les trois icônes (`AppIcon-CyanPulse`,
    /// `AppIcon-MagentaDrift`, `AppIcon-SunsetOverdrive`) sont à produire :
    /// voir `docs/ops/2026-08-19-banque-images-prompts-et-themes-pro.md` §5.4.
    func setAlternateIcon(named name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}
