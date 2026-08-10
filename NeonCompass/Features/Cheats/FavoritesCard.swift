import SwiftUI

/// Les favoris, dans UNE carte plutôt qu'une section de cartes.
///
/// **Ce n'est pas un choix d'apparence.** Une section occupe des places dans la
/// colonne de la liste, et `InlineAdPlacement` distribue ses encarts sur cette
/// colonne : des favoris en section, ce sont des bannières entre eux. Un seul
/// bloc n'offre aucun emplacement. Le raccourci qu'on se garde vers ses cinq
/// codes ne se paie pas d'une publicité au milieu — c'est la raison d'être de
/// cette forme, et ce qu'il ne faut pas défaire en la « simplifiant » en
/// `ForEach` de `CheatCard`.
///
/// Orange et en lueur : c'est la teinte de l'étoile des favoris depuis toujours,
/// et la carte est le seul objet de l'écran qui la porte en grand. La lueur
/// défile avec la liste, donc elle ne consomme pas en permanence l'un des trois
/// accents lumineux que `CLAUDE.md` autorise par écran.
///
/// Elle se répartit en deux : une ombre FIXE sur la carte, une respiration sur la
/// seule étoile de l'en-tête. Voir le commentaire du `shadow` — faire respirer la
/// carte entière a rendu l'écran noir.
struct FavoritesCard: View {
    let cheats: [Cheat]
    let inputMode: CheatInputMode
    let favoriteCount: Int
    let showsCount: Bool
    let isAtCap: Bool
    /// La carte montre-t-elle TOUS les favoris ? Vrai sous le filtre « Favoris »,
    /// où c'est précisément ce qu'on a demandé à voir.
    let showsAll: Bool
    /// L'activité tourne-t-elle ? `nil` quand le bouton n'a pas lieu d'être —
    /// système qui les refuse, ou aucun favori à porter.
    let isPinned: Bool?
    let onSelect: (Cheat) -> Void
    let onRemove: (Cheat) -> Void
    let onShowAll: () -> Void
    let onTogglePin: () -> Void

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Les lignes réellement rendues, plafonnées.
    ///
    /// **Pourquoi un plafond ici alors que le plafond des favoris existe déjà :**
    /// Pro le lève. Un abonné qui étoile les trente-six codes obtiendrait une
    /// carte de trente-six lignes, construites d'un bloc — ce n'est plus un
    /// raccourci, c'est un mur qui repousse le catalogue plusieurs écrans plus
    /// bas. Et une grande carte est précisément ce qui a déjà coûté un écran noir
    /// sur cet écran.
    ///
    /// Sauf sous le filtre « Favoris », où la carte EST tout ce qu'on a demandé à
    /// voir : là, elle les montre tous.
    private var visibleRows: [Cheat] {
        showsAll ? cheats : Array(cheats.prefix(CheatsModel.freeFavoriteCap))
    }

    private var overflow: Int { max(0, cheats.count - visibleRows.count) }

    /// Le pied qui dit ce qu'on ne montre pas, et y mène.
    private var overflowRow: some View {
        Button(action: onShowAll) {
            HStack(spacing: 6) {
                Text("cheats.favorites.more \(overflow)")
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(NCTypography.cardMeta)
            .foregroundStyle(NCColor.sunsetOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // `shown` et non `cheats` : les lignes en trop vivent derrière le
            // pied de carte. Et le filtrage sur le code se fait ICI, avant
            // d'énumérer — le faire dans la boucle laissait passer le filet
            // d'une ligne qui n'était pas rendue, soit un trait tout seul. Une
            // garde qui a l'air défensive et ne l'est pas est pire qu'aucune.
            let shown = visibleRows
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, cheat in
                if index > 0 {
                    // Le filet vit ENTRE les lignes et non sous chacune : une
                    // carte qui se termine par un trait paraît coupée.
                    Rectangle()
                        .fill(NCColor.sunsetOrange.opacity(0.18))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
                row(cheat)
            }
            if overflow > 0 { overflowRow }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NCColor.sunsetOrange.opacity(0.14)), in: .rect(cornerRadius: 20))
        // Le liseré fait le tour de ce que la teinte seule ne délimite pas : sur
        // un fond nuit, un verre orangé à 14 % se lit comme une carte un peu
        // chaude, pas comme un bloc à part.
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(NCColor.sunsetOrange.opacity(0.45), lineWidth: 1)
        )
        // UNE ombre, fixe. Surtout pas `.breathingHighlight` ici, et c'est
        // constaté : posé sur cette carte, il a rendu l'écran ENTIÈREMENT NOIR —
        // l'app vivante à 13 % de CPU, sans jamais présenter une image. Bissecté
        // à variable unique, ce modificateur seul en cause.
        //
        // La raison tient à ce pour quoi il a été écrit : il empile TROIS ombres,
        // dont une de rayon 22, et son coût a été mesuré sur des pastilles de
        // trente points. Une carte pleine largeur de plusieurs centaines de
        // points n'est pas la même chose — le simulateur amplifie fortement le
        // coût des ombres, et trois d'entre elles animées sur cette surface
        // dépassent ce qu'il sait rendre.
        //
        // La respiration reste, mais sur l'étoile de l'en-tête : un petit glyphe,
        // exactement ce pour quoi elle est faite.
        .shadow(color: NCColor.sunsetOrange.opacity(0.35), radius: 12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
                .breathingHighlight(tint: NCColor.sunsetOrange)
            Text("cheats.favorites.title")
                .textCase(.uppercase)
            Spacer()
            if let isPinned { pinButton(isPinned) }
            // Masqué en Pro, où il n'y a pas de plafond : un dénominateur ne
            // dirait rien. Même règle que le carnet d'épingles.
            if showsCount {
                Text(verbatim: "\(favoriteCount)/\(CheatsModel.freeFavoriteCap)")
                    .monospacedDigit()
                    // Magenta au plafond, et il le reste au-delà : quelqu'un peut
                    // avoir plus de cinq favoris d'avant le plafond, et afficher
                    // « 8/5 » est honnête là où truquer le nombre ne le serait pas.
                    .foregroundStyle(isAtCap ? NCColor.sunsetMagenta : NCColor.sunsetOrange.opacity(0.7))
                    .accessibilityLabel(
                        Text("cheats.favorites.countAccessibility \(favoriteCount) \(CheatsModel.freeFavoriteCap)")
                    )
            }
        }
        .font(NCTypography.cardMeta)
        .foregroundStyle(NCColor.sunsetOrange)
        .padding(.bottom, 12)
    }

    /// Une ligne, AVEC OU SANS code.
    ///
    /// Un favori que le mode actif ne sait pas saisir reste ici, et le dit. Le
    /// masquer était le défaut : la carte se vidait en changeant de manette
    /// pendant que le compteur restait plein, et on ne pouvait plus retirer ce
    /// qu'on ne voyait plus. Cinq des trente-six codes de GTA V sont dans ce cas.
    /// Épingler les favoris à l'écran verrouillé — la Live Activity.
    ///
    /// Dans l'en-tête de la CARTE et non sur une ligne : ce qu'on épingle, ce
    /// sont les cinq, pas l'un d'eux. Un bouton par ligne aurait suggéré le
    /// contraire.
    private func pinButton(_ isPinned: Bool) -> some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "lock.badge.clock.fill" : "lock.badge.clock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPinned ? NCColor.sunsetOrange : .secondary)
                .frame(width: 32, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isPinned ? Text("cheats.favorites.unpin") : Text("cheats.favorites.pin")
        )
        .accessibilityAddTraits(isPinned ? [.isSelected] : [])
    }

    private func row(_ cheat: Cheat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                onSelect(cheat)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cheat.effect.resolved(for: currentLanguageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        // Une ligne, coupée s'il le faut : cinq effets entiers
                        // feraient de la carte un mur, et l'effet complet est à
                        // un tap dans le lecteur.
                        .lineLimit(1)
                    // Plus petit que sur une carte de liste — quatorze contre
                    // dix-huit. C'est ce qui fait tenir cinq codes dans un bloc
                    // sans qu'il occupe l'écran entier.
                    if let code = cheat.codes[inputMode] {
                        CheatCodeView(code: code, glyphSize: 14)
                    } else {
                        Text("cheats.favorites.noCodeHere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                onRemove(cheat)
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(NCColor.sunsetOrange)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cheats.favorite.remove"))
        }
        .padding(.vertical, 10)
    }
}
