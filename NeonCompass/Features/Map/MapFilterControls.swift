import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @State private var showFilters = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .trailing, spacing: 12) {
                if showFilters {
                    categoryChips
                }
                HStack(spacing: 12) {
                    searchField
                    filterToggleButton
                }
            }
        }
        .padding(16)
    }

    private var filterToggleButton: some View {
        Button {
            withAnimation(.snappy) { showFilters.toggle() }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var searchField: some View {
        TextField("map.search.placeholder", text: $model.searchQuery)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
    }

    private var categoryChips: some View {
        ForEach(POICategory.allCases, id: \.self) { category in
            let isActive = model.activeCategories.contains(category)
            Button {
                toggle(category)
            } label: {
                Text(category.rawValue)
                    .font(.caption)
                    .foregroundStyle(isActive ? NCColor.neonCyan : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func toggle(_ category: POICategory) {
        if model.activeCategories.contains(category) {
            model.activeCategories.remove(category)
        } else {
            model.activeCategories.insert(category)
        }
    }
}
