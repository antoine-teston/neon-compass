import CoreGraphics

/// Layout constants that don't belong in the color/typography design-system
/// files. `CompactTabBar` has no fixed height of its own (Liquid Glass
/// containers size to content — its tallest element is the 60pt map button,
/// floated -12pt above the row), so this is a deliberately approximate,
/// hand-tuned clearance value rather than a measured one. Re-tune if
/// `CompactTabBar`'s content changes.
enum NCLayout {
    static let compactTabBarClearance: CGFloat = 78

    /// Réserve haute pour `AppHeaderBar`, et de la même nature approximative que
    /// la réserve basse ci-dessus : le verre se dimensionne à son contenu, il n'y
    /// a donc pas de hauteur à mesurer. La capsule fait une vingtaine de points
    /// de contenu et deux fois dix de marge ; le reste sépare la barre du premier
    /// élément de l'écran.
    ///
    /// `RootView` l'applique lui-même en `safeAreaPadding` : aucun écran n'a à
    /// s'en souvenir, contrairement à la réserve basse que chacun pose à la main.
    static let headerBarClearance: CGFloat = 48
}
