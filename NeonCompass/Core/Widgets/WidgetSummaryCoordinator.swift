import Foundation
import Observation

/// Composes the full `WidgetSummary` from pieces owned by two unrelated
/// screens (Progression's overall progress, Cheats' favorite cheat title)
/// plus the current Pro entitlement, without either feature model knowing
/// about the other. Constructed once at `RootView` and shared via
/// `.environment(_:)`, matching the app's established shared-instance
/// pattern (e.g. `ProEntitlementModel`).
///
/// Every update writes the FULL composed summary — a widget process only
/// ever reads `WidgetSummary` in one piece, so a partial write (e.g.
/// progress alone, still carrying the stale favorite title) would be
/// incoherent, not just incomplete.
@Observable
@MainActor
final class WidgetSummaryCoordinator {
    private let writer: WidgetSummaryWriting
    private let proEntitlementModel: ProEntitlementModel

    private var overallProgress: Double = 0
    private var favoriteCheatTitle: String?

    init(writer: WidgetSummaryWriting, proEntitlementModel: ProEntitlementModel) {
        self.writer = writer
        self.proEntitlementModel = proEntitlementModel
    }

    func updateProgress(_ progress: Double) {
        overallProgress = progress
        writeSummary()
    }

    func updateFavoriteCheat(_ title: String?) {
        favoriteCheatTitle = title
        writeSummary()
    }

    private func writeSummary() {
        writer.write(
            WidgetSummary(
                isProEntitled: proEntitlementModel.isProEntitled,
                overallProgress: overallProgress,
                favoriteCheatTitle: favoriteCheatTitle
            )
        )
    }
}
