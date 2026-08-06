import SwiftUI

struct SettingsNotificationsSection: View {
    let store: FollowedCategoriesStore

    var body: some View {
        Section("settings.section.notifications") {
            ForEach(POICategory.allCases, id: \.self) { category in
                Toggle(isOn: Binding(
                    get: { store.followedCategories.contains(category) },
                    set: { _ in Task { await store.toggle(category) } }
                )) {
                    Text(category.localizedNameKey)
                }
            }
        }
    }
}
