import CoreGraphics

/// Layout constants that don't belong in the color/typography design-system
/// files. `CompactTabBar` has no fixed height of its own (Liquid Glass
/// containers size to content — its tallest element is the 60pt map button,
/// floated -12pt above the row), so this is a deliberately approximate,
/// hand-tuned clearance value rather than a measured one. Re-tune if
/// `CompactTabBar`'s content changes.
enum NCLayout {
    static let compactTabBarClearance: CGFloat = 78
}
