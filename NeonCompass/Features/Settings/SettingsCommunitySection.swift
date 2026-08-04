import SwiftUI

struct SettingsCommunitySection: View {
    let communityModel: CommunityModel

    var body: some View {
        Section("settings.section.community") {
            let blocked = communityModel.blockedContributors
            if blocked.isEmpty {
                Text("profile.blockedContributors.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blocked) { contributor in
                    HStack {
                        Text(label(for: contributor))
                        Spacer()
                        Button("profile.blockedContributors.unblock") {
                            communityModel.unblock(authorUid: contributor.uid)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    /// Le pseudo enregistré au blocage, sinon un UID tronqué — les lignes
    /// bloquées avant que le pseudo ne soit conservé n'en ont pas, et le client
    /// ne peut pas le retrouver (RLS : on ne lit que sa propre ligne).
    private func label(for contributor: BlockedContributorSummary) -> String {
        if let handle = contributor.handle, !handle.isEmpty { return handle }
        let short = contributor.uid.prefix(4).uppercased()
        return String(format: String(localized: "profile.blockedContributors.unknown %@"), "\(short)…")
    }
}
