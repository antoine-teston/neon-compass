import SwiftUI

/// Une de MES propositions, pas encore publique.
///
/// Elle n'est visible que par son auteur, et pour une raison simple : elle
/// n'existe nulle part ailleurs. Avant l'ouverture du jeu à venir, sa carte est
/// vide — cette épingle est la seule chose qui y apparaisse pour quelqu'un qui
/// vient de la remplir.
///
/// Autonome, comme `ContributionAnnotationView` : elle porte son propre popover
/// plutôt que de passer par `MapSelection`, qui ne connaît que les POI et les
/// épingles du carnet.
///
/// **Ni signaler ni masquer ici**, contrairement à une proposition publiée. La
/// directive Apple 1.2 vise l'UGC d'AUTRUI ; se signaler soi-même n'a pas de
/// sens, et l'auteur n'a rien à modérer sur son propre brouillon.
struct PendingContributionAnnotationView: View {
    let spot: Contribution
    let style: MapStyle

    @State private var showDetail = false

    /// Anneau pointillé, comme `draftPin` et comme l'épingle de placement : dans
    /// ce moteur, le pointillé veut dire « pas encore publié ». La couleur reste
    /// celle de la catégorie, pour que la proposition ne change pas d'allure en
    /// passant de la pose à l'attente.
    var body: some View {
        let tint = POIPinPalette.color(for: spot.category, style: style)
        Button {
            showDetail = true
        } label: {
            Image(systemName: POIPinPalette.symbol(for: spot.category))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(POIPinPalette.core(for: style).opacity(0.82))
                        .overlay(
                            Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                        )
                )
                .pinHitArea(side: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spot.title))
        .accessibilityValue(Text(statusKey))
        .popover(isPresented: $showDetail) {
            detail
                .padding(16)
                .frame(minWidth: 240)
        }
    }

    /// Deux phrases pour un seul dessin. « Approuvée » n'est pas un cas
    /// théorique : entre le geste du modérateur et la reconstruction du
    /// fragment, il s'écoule des minutes — parfois un lancement.
    private var statusKey: LocalizedStringKey {
        spot.status == .approved ? "map.contribution.pending.approved" : "map.contribution.pending.status"
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(spot.title)
                    .font(NCTypography.body)
                Spacer()
                Text("map.contribution.pending.badge")
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
            }
            Text(spot.category.localizedNameKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label {
                Text(statusKey)
            } icon: {
                Image(systemName: spot.status == .approved ? "checkmark.circle" : "clock")
            }
            .font(.caption)
            .foregroundStyle(spot.status == .approved ? NCColor.neonCyan : NCColor.sunsetOrange)
        }
    }
}
