import SwiftUI

/// Le classement des contributeurs. Se lit sans compte — y figurer en demande
/// un, ce que `submitContribution` impose déjà côté serveur.
struct LeaderboardSection: View {
    let rows: [LeaderboardRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Même motif que les titres du volet Propositions : le gras suffit à
            // marquer une section, l'accent est réservé à ce qu'un écran veut
            // vraiment faire remarquer — ici, le rebours de la carte au-dessus.
            Text("social.leaderboard.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white.opacity(0.85))

            if rows.isEmpty {
                Text("social.leaderboard.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            // `verbatim` : un rang nu n'a rien à traduire, mais sans ça
                            // SwiftUI en fait la clé `%lld` et l'extracteur la reverse
                            // dans le catalogue comme une souche vide. Cf. ProgressRing.
                            Text(verbatim: "\(index + 1)")
                                .font(NCTypography.body.bold())
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 32, alignment: .leading)
                            Text(row.handle)
                                .font(NCTypography.body)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("social.leaderboard.spots \(row.approvedCount)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        if index < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
