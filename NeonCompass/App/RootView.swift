import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var onboarding = OnboardingModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            PlaceholderScreen(tab: model.selectedTab)
            CompactTabBar(selection: $model.selectedTab)
        }
    }

    private var regularLayout: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    PlaceholderScreen(tab: tab)
                } label: {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
