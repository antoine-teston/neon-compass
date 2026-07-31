import SwiftUI

/// Entête du Profil. Reste lisible dans les deux états : hors connexion, un
/// titre neutre remplace le pseudo plutôt que d'afficher un mur de connexion,
/// et le bouton de réglages reste atteignable connecté comme déconnecté.
struct ProfileHeaderView: View {
    let profile: Profile?
    let isSignedIn: Bool
    let isProEntitled: Bool
    let pendingContributionCount: Int
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isSignedIn ? (profile?.handle ?? "…") : String(localized: "profile.header.anonymous"))
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.neonCyan)
                    if isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(NCColor.neonCyan)
                    }
                }
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("settings.title"))
            }

            if let profile {
                HStack {
                    Text(String(format: String(localized: "profile.level.format"), profile.level))
                        .font(NCTypography.body.bold())
                        .foregroundStyle(NCColor.neonCyan)
                    Spacer()
                    Text(String(format: String(localized: "profile.xp.format"), profile.xp))
                        .font(NCTypography.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                // L'XP ne se gagne que sur les contributions APPROUVÉES : entre
                // l'envoi et la modération, le rang ne bouge pas. Sans cette
                // ligne, le contributeur subit un silence inexplicable.
                if pendingContributionCount > 0 {
                    Text("profile.pending \(pendingContributionCount)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
