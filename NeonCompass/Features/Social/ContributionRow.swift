import SwiftUI

/// Une proposition dans le volet Social : ce qu'elle est, qui l'a posée, et les
/// deux votes **avec mon état** — que la carte n'affichait pas.
struct ContributionRow: View {
    let spot: Contribution
    let myVote: VoteDirection?
    let onVote: (VoteDirection) -> Void
    let onReport: () -> Void
    let onBlockAuthor: () -> Void

    @State private var showBlockConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // Blanc et non cyan : cette ligne se répète à chaque
                // proposition, et la date qui la suit était déjà en blanc — le
                // cyan ne distinguait donc pas, il criait.
                Text(spot.category.localizedNameKey)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                if let relative = relativeDate {
                    Text(verbatim: "·")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(relative)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }

            Text(spot.title)
                .font(NCTypography.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Text(spot.authorHandle)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 12) {
                voteButton(.up, symbol: "arrow.up", count: spot.upvotes)
                voteButton(.down, symbol: "arrow.down", count: spot.downvotes)
                Spacer()
                // Signaler et masquer : la directive Apple 1.2 les exige partout
                // où de l'UGC s'affiche, donc ici comme sur la carte.
                Menu {
                    Button("map.spot.report", action: onReport)
                    if spot.authorUid != nil {
                        Button("map.spot.blockAuthor", role: .destructive) {
                            showBlockConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("map.spot.report"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .confirmationDialog(
            Text(String(format: String(localized: "map.spot.blockConfirmTitle"), spot.authorHandle)),
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("map.spot.blockConfirm", role: .destructive, action: onBlockAuthor)
            Button("map.spot.blockCancel", role: .cancel) {}
        } message: {
            Text("map.spot.blockConfirmMessage")
        }
    }

    /// Mon vote se voit : rempli et cyan quand c'est le mien, creux sinon. C'est
    /// exactement ce qui manquait — rien ne distinguait « je n'ai pas voté » de
    /// « j'ai voté pour », et on pouvait retaper indéfiniment sans le savoir.
    private func voteButton(_ direction: VoteDirection, symbol: String, count: Int) -> some View {
        let isMine = myVote == direction
        return Button {
            onVote(direction)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isMine ? "\(symbol).circle.fill" : "\(symbol).circle")
                Text(verbatim: "\(count)")
            }
            .font(NCTypography.cardMeta)
            .foregroundStyle(isMine ? NCColor.neonCyan : .white.opacity(0.6))
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }

    /// `nil` quand la date manque — la ligne perd sa mention, elle ne perd pas
    /// sa place.
    ///
    /// Pas de `now` reçu en paramètre : `.relative` se compare à l'instant du
    /// rendu et n'accepte pas de date de référence. Un `now` passé de l'écran
    /// serait donc une propriété morte, et la minuterie de `SocialScreen`
    /// reconstruit déjà la vue chaque minute — la mention se rafraîchit sans
    /// qu'on ait à la piloter.
    private var relativeDate: String? {
        guard let date = spot.approvedAtDate else { return nil }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
