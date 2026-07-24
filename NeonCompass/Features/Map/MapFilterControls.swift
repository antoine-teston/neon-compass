import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @State private var showFilters = false
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

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
                if proEntitlementModel.isProEntitled {
                    hideFoundButton
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

    private var hideFoundButton: some View {
        Button {
            model.hideFoundPOIs.toggle()
        } label: {
            Text("map.hideFound.toggle")
                .font(.caption)
                .foregroundStyle(model.hideFoundPOIs ? NCColor.neonCyan : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
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
                Text(category.localizedNameKey)
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
