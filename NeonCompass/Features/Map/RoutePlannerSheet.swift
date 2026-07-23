import SwiftUI

/// Pro-only numbered list of the greedy nearest-neighbor route over the
/// remaining (not-yet-found) collectibles, computed by the caller and
/// handed in as an already-ordered array — this view is purely presentational.
struct RoutePlannerSheet: View {
    let route: [POI]
    let languageCode: String

    var body: some View {
        NavigationStack {
            Group {
                if route.isEmpty {
                    ContentUnavailableView(
                        "map.routePlanner.empty",
                        systemImage: "checkmark.seal"
                    )
                } else {
                    List {
                        ForEach(Array(route.enumerated()), id: \.element.id) { index, poi in
                            HStack {
                                Text(String(format: String(localized: "map.routePlanner.stepFormat"), index + 1))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(poi.title.resolved(for: languageCode))
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("map.routePlanner.title"))
        }
    }
}
