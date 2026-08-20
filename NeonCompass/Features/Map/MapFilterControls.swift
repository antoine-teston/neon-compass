import SwiftUI

struct MapFilterControls: View {
    @Bindable var model: MapModel
    @Binding var showPersonalPins: Bool
    @Binding var showPersonalPinList: Bool
    /// Entrée DIRECTE en mode parcours — plus de feuille intermédiaire.
    let onStartRoute: () -> Void
    @State private var showFilters = false
    @Environment(ProEntitlementModel.self) private var proEntitlementModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    notebookButton
                    if proEntitlementModel.isProEntitled {
                        routePlannerButton
                    }
                    searchField
                    filterToggleButton
                }
            }
            GlassEffectContainer(spacing: 12) {
                VStack(alignment: .trailing, spacing: 12) {
                    if showFilters {
                        categoryChips
                        personalPinsChip
                    }
                    if proEntitlementModel.isProEntitled {
                        hideFoundButton
                    }
                }
            }
        }
        .padding(16)
    }

    /// Le glyphe était une étoile et le nom disait « favoris » : ce bouton n'a
    /// jamais ouvert des favoris, il ouvre le carnet d'épingles. Une épingle le
    /// dit, et fait écho aux gouttes posées sur la carte.
    private var notebookButton: some View {
        Button {
            showPersonalPinList = true
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("map.personalPins.title"))
    }

    private var routePlannerButton: some View {
        Button {
            onStartRoute()
        } label: {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("map.routePlanner.title"))
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
            .frame(maxWidth: .infinity)
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

    /// Les épingles échappaient à TOUS les filtres — les puces de catégorie ne
    /// les concernaient pas, « masquer les trouvés » non plus. Elle est en
    /// `sunsetOrange` et non en cyan comme les catégories : c'est la teinte du
    /// calque qu'elle commande.
    private var personalPinsChip: some View {
        Button {
            showPersonalPins.toggle()
        } label: {
            Text("map.filter.pins")
                .font(.caption)
                .foregroundStyle(showPersonalPins ? NCColor.sunsetOrange : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func toggle(_ category: POICategory) {
        if model.activeCategories.contains(category) {
            model.activeCategories.remove(category)
        } else {
            model.activeCategories.insert(category)
        }
    }
}
