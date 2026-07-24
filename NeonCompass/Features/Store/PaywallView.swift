import SwiftUI

private struct FixedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .font(.system(size: 18))
                .frame(width: 24, alignment: .center)
            configuration.title
        }
    }
}

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
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("paywall.subtitle")
                        .font(NCTypography.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(features, id: \.1) { feature in
                            Label(feature.0, systemImage: feature.1)
                                .foregroundStyle(.white)
                        }
                    }
                    .labelStyle(FixedIconLabelStyle())
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .labelStyle(FixedIconLabelStyle())
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
