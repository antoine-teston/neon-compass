import SwiftUI

struct CheatsListView: View {
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                platformToggle
                TextField("cheats.search.placeholder", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)

                ForEach(model.filteredCheats) { cheat in
                    CheatCard(
                        cheat: cheat,
                        platform: model.activePlatform,
                        isFavorite: model.isFavorite(cheat),
                        onTap: { onSelect(cheat) },
                        onToggleFavorite: { model.toggleFavorite(cheat) }
                    )
                }
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var platformToggle: some View {
        Picker("cheats.platform.picker", selection: $model.activePlatform) {
            Text("cheats.platform.ps5").tag(Platform.ps5)
            Text("cheats.platform.xbox").tag(Platform.xbox)
        }
        .pickerStyle(.segmented)
    }
}
