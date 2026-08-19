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
    /// Ce qui a fait apparaître cet écran, quand c'est un refus et non un choix.
    ///
    /// Sans elle, buter sur le plafond des favoris ouvrait un écran Pro générique :
    /// l'étoile ne s'allumait pas, une page de vente surgissait, et c'était à
    /// l'utilisateur de faire le lien. Une phrase suffit à le faire pour lui.
    ///
    /// `nil` quand on vient l'ouvrir soi-même, depuis les réglages ou le profil —
    /// là, personne n'a besoin qu'on lui rappelle ce qu'il vient de demander.
    var reason: LocalizedStringKey?

    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(\.dismiss) private var dismiss

    @Environment(ServerFeaturesModel.self) private var serverFeatures

    /// Les notifications de catégorie suivie sont envoyées par une Cloud
    /// Function. Tant qu'elle n'est pas déployée, les annoncer serait vendre ce
    /// qu'on ne livre pas — et c'est un motif de rejet App Store documenté, pas
    /// seulement une maladresse. La ligne revient d'elle-même le jour où le
    /// drapeau serveur passe à vrai.
    private var features: [(LocalizedStringKey, String)] {
        var features: [(LocalizedStringKey, String)] = [
            ("paywall.feature.ads", "nosign"),
            ("paywall.feature.sync", "icloud"),
            ("paywall.feature.unlimited", "pin"),
            ("paywall.feature.route", "map"),
            ("paywall.feature.hideFound", "eye.slash"),
            ("paywall.feature.widget", "square.grid.2x2"),
            ("paywall.feature.lockScreen", "lock"),
        ]
        if serverFeatures.isEnabled {
            features.append(("paywall.feature.notifications", "bell"))
        }
        features.append(("paywall.feature.themes", "paintpalette"))
        return features
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                VStack(spacing: 24) {
                    // Le dégradé de marque : cet écran vend Pro, et Pro est
                    // désormais de la famille chaude — cf. le badge de l'entête
                    // du Profil. Le bouton d'achat était déjà en magenta.
                    if let reason {
                        Text(reason)
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(NCColor.sunsetOrange)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text("paywall.title")
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.sunset)
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
                            .foregroundStyle(NCColor.sunsetOrange)
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
