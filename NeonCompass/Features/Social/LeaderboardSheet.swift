import SwiftUI

/// La vue complète du classement : podium, puis la liste à partir du 4ᵉ.
struct LeaderboardSheet: View {
    let rows: [LeaderboardRow]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        LeaderboardPodium(rows: rows)
                        if rows.count > 3 {
                            LeaderboardSection(rows: Array(rows.dropFirst(3)), startRank: 4)
                        }
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
            .navigationTitle(Text("social.leaderboard.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
