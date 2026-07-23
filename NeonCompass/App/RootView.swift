import GoogleMobileAds
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var onboarding = OnboardingModel()
    @State private var authModel = AuthModel(authProvider: FirebaseAuthProvider())
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if onboarding.needsATTPrompt {
                ProgressView()
                    .task { await onboarding.requestTrackingAuthorization() }
            } else if onboarding.needsConsentPrompt {
                ProgressView()
                    .task { await onboarding.requestConsent() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .environment(authModel)
        .preferredColorScheme(.dark)
        // Starts Mobile Ads only once every onboarding gate (disclaimer,
        // ATT, UMP consent) has cleared — never before consent is resolved
        // (spec §RGPD: consent gate is mandatory, not bypassable). Keyed on
        // needsConsentPrompt (the last gate to flip false) so this fires
        // exactly once, right after that transition, rather than re-running
        // on every unrelated state change.
        .task(id: onboarding.needsConsentPrompt) {
            guard !onboarding.needsDisclaimer, !onboarding.needsATTPrompt, !onboarding.needsConsentPrompt else { return }
            MobileAds.shared.start()
        }
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            screen(for: model.selectedTab)
            CompactTabBar(selection: $model.selectedTab)
        }
    }

    private var regularLayout: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    screen(for: tab)
                } label: {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .progress: ProgressionScreen()
        case .profile: ProfileScreen()
        }
    }
}
