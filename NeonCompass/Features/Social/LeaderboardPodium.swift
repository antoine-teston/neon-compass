import SwiftUI

/// Le podium top 3 de la vue complète. Le moment « gloire » du classement —
/// il vit dans la feuille, pas au premier écran.
struct LeaderboardPodium: View {
    let rows: [LeaderboardRow]

    /// 2ᵉ, 1ᵉʳ, 3ᵉ — l'ordre spatial d'un podium. Pur, donc testé, y compris
    /// avec moins de trois lignes.
    static func displayOrder(_ rows: [LeaderboardRow]) -> [LeaderboardRow] {
        let top = Array(rows.prefix(3))
        switch top.count {
        case 3: return [top[1], top[0], top[2]]
        case 2: return [top[1], top[0]]
        default: return top
        }
    }

    var body: some View {
        let ordered = Self.displayOrder(rows)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(ordered) { row in
                let rank = (rows.firstIndex(of: row) ?? 0) + 1
                step(row: row, rank: rank)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func step(row: LeaderboardRow, rank: Int) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(rank == 1 ? 0.16 : 0.08))
                .frame(height: rank == 1 ? 84 : rank == 2 ? 62 : 48)
                .overlay(alignment: .top) {
                    // Le rang, jamais traduit : `verbatim`, comme les rangs de
                    // `LeaderboardSection`.
                    Text(verbatim: "\(rank)")
                        .font(NCTypography.cardTitle)
                        .foregroundStyle(rank == 1 ? NCColor.sunsetOrange : .white.opacity(0.4))
                        .padding(.top, 8)
                }
            Text(row.handle)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("social.leaderboard.spots \(row.approvedCount)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
