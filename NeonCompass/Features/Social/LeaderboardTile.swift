import SwiftUI

/// Le classement, rétrogradé en tuile : le meneur et mon rang. Le podium et le
/// top 50 vivent dans la vue complète — il retrouvera de la place quand la
/// base de contributeurs le justifiera.
struct LeaderboardTile: View {
    let rows: [LeaderboardRow]
    let myRank: Int?
    let onOpen: () -> Void

    var body: some View {
        HubTile(titleKey: "social.leaderboard.title", action: onOpen) {
            if let leader = rows.first {
                Text("social.hub.leaderboard.leader \(leader.handle)")
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        } sub: {
            if let myRank {
                Text("social.hub.leaderboard.myRank \(myRank)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("social.hub.leaderboard.contributors \(rows.count)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
