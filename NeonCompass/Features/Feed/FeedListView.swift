import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.newsItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.newsItems) { item in
                            card(for: item)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, proEntitlementModel.isProEntitled ? 0 : bannerClearance)
            }
            if !proEntitlementModel.isProEntitled {
                adBanner
            }
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    /// 150pt covers `BannerAdView`'s clamped `maxAdHeight` ceiling (the
    /// documented legitimate max for `largeAnchoredAdaptiveBanner`, per
    /// `GADAdSize.h`'s 50–150pt range) plus the bubble's own padding — the
    /// exact ad height is only known at runtime (it depends on device
    /// width), so this reserved-space constant is a deliberately
    /// conservative upper-bound estimate, not a measurement.
    private var bannerClearance: CGFloat {
        (sizeClass == .compact ? NCLayout.compactTabBarClearance : 0) + 150
    }

    private var adBanner: some View {
        BannerAdView()
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
    }

    private func card(for item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            Text(item.title.resolved(for: currentLanguageCode))
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)

            Text(item.body.resolved(for: currentLanguageCode))
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.system(size: 32))
                .foregroundStyle(NCColor.neonCyan)
            Text("feed.empty")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private func categoryTitleKey(_ category: NewsCategory) -> LocalizedStringKey {
        switch category {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        }
    }

    private func categorySymbol(_ category: NewsCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        }
    }
}
