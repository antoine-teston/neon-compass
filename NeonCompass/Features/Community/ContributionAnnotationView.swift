import SwiftUI

struct ContributionAnnotationView: View {
    let spot: Contribution
    let onVote: (VoteDirection) -> Void
    let onReport: () -> Void
    let onBlockAuthor: () -> Void
#if DEBUG
    /// Passerelle communauté → éditorial : non nil seulement quand le mode
    /// éditeur est armé. La foule repère, on vérifie en jeu, un tap en fait du
    /// contenu qui compte dans la progression et les défis.
    var onAdopt: (() -> Void)?
#endif

    @State private var showDetail = false
    @State private var showBlockConfirmation = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(NCColor.neonCyan)
        }
        .popover(isPresented: $showDetail) {
            detail
                .padding(16)
                .frame(minWidth: 260)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(spot.title)
                    .font(NCTypography.body)
                Spacer()
                Text("map.spot.communityBadge")
                    .font(.caption)
                    .foregroundStyle(NCColor.sunsetMagenta)
            }
            Text(spot.authorHandle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    onVote(.up)
                } label: {
                    Label("\(spot.upvotes)", systemImage: "arrow.up")
                }
                Button {
                    onVote(.down)
                } label: {
                    Label("\(spot.downvotes)", systemImage: "arrow.down")
                }
                Spacer()
                Button("map.spot.report", action: onReport)
                if let authorUid = spot.authorUid {
                    Button("map.spot.blockAuthor") {
                        showBlockConfirmation = true
                    }
                    .confirmationDialog(
                        Text(String(format: String(localized: "map.spot.blockConfirmTitle"), spot.authorHandle)),
                        isPresented: $showBlockConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("map.spot.blockConfirm", role: .destructive) {
                            onBlockAuthor()
                            showDetail = false
                        }
                        Button("map.spot.blockCancel", role: .cancel) {}
                    } message: {
                        Text("map.spot.blockConfirmMessage")
                    }
                    .id(authorUid) // scope the confirmationDialog state to this spot's author
                }
            }

#if DEBUG
            if let onAdopt {
                Button("Adopter en POI éditorial", systemImage: "square.and.arrow.down") {
                    onAdopt()
                    showDetail = false
                }
                .font(.caption)
            }
#endif
        }
    }
}
