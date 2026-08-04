import SwiftUI

struct ContributionAnnotationView: View {
    let spot: Contribution
    /// Reçu et non supposé : le cœur de la goutte s'écarte du fond, et les deux
    /// habillages n'ont pas le même fond. En dur, l'épingle serait noire sur la
    /// carte d'origine, qui est claire.
    let style: MapStyle
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

    /// Même goutte que les épingles personnelles, en teinte communautaire.
    ///
    /// Elle était un `mappin.circle.fill` cyan — soit la couleur de la catégorie
    /// « activité », et une troisième silhouette pour une carte qui n'en avait
    /// pas besoin. Le magenta est celui que portent déjà sa pastille de groupe et
    /// son badge de fiche ; la goutte dit « posée par quelqu'un », par opposition
    /// aux disques du contenu éditorial.
    var body: some View {
        Button {
            showDetail = true
        } label: {
            DroppedPinView(
                symbol: "mappin",
                tint: NCColor.sunsetMagenta,
                style: style,
                accessibilityTitle: spot.title
            )
        }
        .buttonStyle(.plain)
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
            // La catégorie n'était affichée NULLE PART, alors qu'on la choisit à
            // la soumission.
            HStack(spacing: 6) {
                Text(spot.category.localizedNameKey)
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
                Text(verbatim: "·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(spot.authorHandle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Les compteurs, en LECTURE. On vote dans le volet Social, où l'on
            // voit son propre état de vote et où la file se parcourt ; ce
            // popover dit ce qu'il y a là, il ne demande plus d'arbitrer.
            //
            // `verbatim` : un décompte nu n'a rien à traduire, et sans ça
            // SwiftUI en fait la clé de localisation « %lld », qui finit en
            // souche vide dans le catalogue.
            HStack(spacing: 16) {
                Label {
                    Text(verbatim: "\(spot.upvotes)")
                } icon: {
                    Image(systemName: "arrow.up")
                }
                Label {
                    Text(verbatim: "\(spot.downvotes)")
                } icon: {
                    Image(systemName: "arrow.down")
                }
                Spacer()
                // Signaler et masquer RESTENT : la directive Apple 1.2 les exige
                // partout où de l'UGC s'affiche, donc ici comme dans la liste.
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
