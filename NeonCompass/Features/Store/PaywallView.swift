import SwiftUI

struct PaywallView: View {
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.dismiss) private var dismiss

    private let features: [(LocalizedStringKey, String)] = [
        ("paywall.feature.ads", "nosign"),
        ("paywall.feature.sync", "icloud"),
        ("paywall.feature.route", "map"),
        ("paywall.feature.remaining", "checklist"),
        ("paywall.feature.widgets", "square.grid.2x2"),
        ("paywall.feature.notifications", "bell"),
        ("paywall.feature.themes", "paintpalette"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                VStack(spacing: 24) {
                    Text("paywall.title")
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.neonCyan)
                    Text("paywall.subtitle")
                        .font(NCTypography.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(features, id: \.1) { feature in
                            Label(feature.0, systemImage: feature.1)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(NCColor.neonCyan)
                    } else {
                        Button("paywall.buy") {
                            Task { await proEntitlementModel.purchase() }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(NCColor.sunsetMagenta)

                        Button("paywall.restore") {
                            Task { await proEntitlementModel.restorePurchases() }
                        }
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("paywall.close") { dismiss() }
                }
            }
        }
    }
}
