import SwiftUI

struct SettingsNotificationsSection: View {
    let store: FollowedCategoriesStore

    var body: some View {
        Section {
            ForEach(POICategory.allCases, id: \.self) { category in
                Toggle(isOn: Binding(
                    get: { store.followedCategories.contains(category) },
                    set: { _ in Task { await store.toggle(category) } }
                )) {
                    Text(category.localizedNameKey)
                }
            }
        } header: {
            SettingsIconLabel(
                "settings.section.notifications",
                systemImage: "bell.badge.fill",
                tint: NCColor.sunsetMagenta
            )
        }
    }
}
