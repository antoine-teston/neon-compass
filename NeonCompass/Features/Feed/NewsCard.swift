import SwiftUI

/// Une entrée du fil, en résumé.
///
/// Deux tailles et non deux vues : la ligne d'informations, le point de
/// nouveauté et le geste d'ouverture sont identiques dans les deux cas, et
/// c'est la partie qu'on aurait recopiée.
struct NewsCard: View {
    /// Le poids visuel de la carte dans le fil.
    ///
    /// `featured` n'est donné qu'à l'entrée la plus récente. C'est ce qui casse
    /// la platitude d'une colonne où six cartes de verre identiques se lisaient
    /// toutes au même poids — sans inventer de couleur, puisque le contenu ne
    /// porte pas d'image et qu'aucun de ses champs ne distingue une annonce
    /// majeure d'une brève.
    enum Prominence {
        case featured
        case standard
    }

    let item: NewsItem
    let prominence: Prominence
    let isNew: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: prominence == .featured ? 10 : 6) {
                metaRow

                Text(item.title.resolved(for: currentLanguageCode))
                    .font(prominence == .featured ? NCTypography.featuredTitle : NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(prominence == .featured ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: 8) {
                    Text(item.body.resolved(for: currentLanguageCode))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        // Trois lignes sur une carte ordinaire : assez pour
                        // décider si on veut lire, et c'est ce qui garde
                        // plusieurs entrées à l'écran. La une en prend une de
                        // plus, puisque c'est elle qu'on veut voir en premier.
                        .lineLimit(prominence == .featured ? 4 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Le chevron est la seule chose qui dit que la carte ouvre
                    // quelque chose. Sans lui, le texte coupé se lit comme une
                    // troncature subie, pas comme une invitation.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(prominence == .featured ? 18 : 14)
            .glassEffect(.regular, in: .rect(cornerRadius: prominence == .featured ? 20 : 14))
        }
        // Sans style « plain », le bouton teinte tout son contenu de la couleur
        // d'accentuation — titre, corps et pastille comprises.
        .buttonStyle(.plain)
        .accessibilityHint("feed.card.open")
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            // L'icône garde l'accent, le libellé passe en blanc : le mot ne fait
            // que redire ce que l'icône montre déjà, et une colonne de six
            // cartes en faisait six accents cyan (voir `NCColor.neonCyan`).
            Label {
                Text(item.category.titleKey)
                    .foregroundStyle(.white.opacity(0.55))
            } icon: {
                Image(systemName: item.category.symbolName)
                    .foregroundStyle(NCColor.neonCyan)
            }
            .font(NCTypography.cardMeta)

            gameBadge

            Spacer(minLength: 8)

            if isNew {
                // Magenta et non cyan : la ligne porte déjà une icône cyan à
                // deux doigts de là, et deux accents de la même couleur sur la
                // même ligne ne se distinguent plus l'un de l'autre.
                Circle()
                    .fill(NCColor.sunsetMagenta)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("feed.new")
            }

            if let date = formattedDate {
                Text(date)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// « VI » ou « V », et rien d'autre.
    ///
    /// Le fil couvre les deux jeux, donc un lecteur doit savoir en un coup d'œil
    /// duquel on lui parle — sinon un braquage du jeu en ligne actuel se lit
    /// comme une révélation sur celui à venir. Pas de texte localisé ici : un
    /// chiffre romain se lit dans les cinq langues.
    ///
    /// Volontairement neutre pour le jeu à venir et discret pour l'autre : c'est
    /// une aide au repérage, pas un troisième accent lumineux sur l'écran
    /// (CLAUDE.md : au plus trois par écran, et le cyan en prend déjà un).
    private var gameBadge: some View {
        Text(item.game.shortLabel)
            .font(NCTypography.cardMeta)
            .foregroundStyle(.white.opacity(item.game == .leonida ? 0.7 : 0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.08), in: .capsule)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private var formattedDate: String? {
        item.publishedDate?.formatted(.dateTime.day().month(.abbreviated))
    }
}
