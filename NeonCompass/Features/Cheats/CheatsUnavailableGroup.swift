import SwiftUI

/// Les triches que le mode actif ne permet pas de saisir.
///
/// Repliées en bas de liste plutôt que masquées : cinq des trente-six codes de
/// GTA V n'ont aucun combo manette — dont trois véhicules, qu'on cherche par
/// leur nom — et les masquer ferait croire à un joueur console qu'ils
/// n'existent pas. Repliées plutôt qu'en ligne : la liste dépliée sert le scan
/// rapide, qui est la raison d'être de l'écran.
struct CheatsUnavailableGroup: View {
    let cheats: [Cheat]
    @Bindable var model: CheatsModel
    let onSelect: (Cheat) -> Void

    @State private var isExpanded = false

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("cheats.unavailable.title \(cheats.count)")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(cheats) { cheat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cheat.resolvedShortEffect(for: currentLanguageCode))
                            .font(NCTypography.body)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                        // Le tap ne se contente pas d'informer : il emmène
                        // l'utilisateur dans le mode où le code existe.
                        HStack(spacing: 8) {
                            ForEach(model.modesAvailable(for: cheat), id: \.self) { mode in
                                Button {
                                    model.activeInputMode = mode
                                    onSelect(cheat)
                                } label: {
                                    Label(
                                        String(localized: mode.label),
                                        systemImage: mode.symbolName
                                    )
                                    .font(.caption.bold())
                                }
                                .buttonStyle(.glassProminent)
                                .tint(NCColor.sunsetViolet)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

extension CheatInputMode {
    /// Nom complet, pour les phrases et l'accessibilité.
    var label: LocalizedStringResource {
        switch self {
        case .playstation: "cheats.mode.playstation"
        case .xbox: "cheats.mode.xbox"
        case .pc: "cheats.mode.pc"
        case .phone: "cheats.mode.phone"
        }
    }

    /// Nom court, pour le segmenté : quatre segments dont l'un dirait
    /// « Manette PlayStation » en entier tronqueraient tous les autres en
    /// largeur compacte.
    var shortLabel: LocalizedStringResource {
        switch self {
        case .playstation: "cheats.mode.playstation.short"
        case .xbox: "cheats.mode.xbox.short"
        case .pc: "cheats.mode.pc.short"
        case .phone: "cheats.mode.phone.short"
        }
    }

    /// Les deux familles de manette partagent `gamecontroller.fill` : aucun
    /// glyphe propriétaire. Ce symbole ne sert donc qu'aux boutons du groupe
    /// ci-dessus, où le libellé lève l'ambiguïté — jamais au segmenté, qui les
    /// rendrait indistinguables.
    var symbolName: String {
        switch self {
        case .playstation, .xbox: "gamecontroller.fill"
        case .pc: "keyboard.fill"
        case .phone: "iphone.gen3"
        }
    }
}

extension CheatCategory {
    var label: LocalizedStringResource {
        switch self {
        case .player: "cheats.category.player"
        case .weapons: "cheats.category.weapons"
        case .vehicles: "cheats.category.vehicles"
        case .world: "cheats.category.world"
        case .misc: "cheats.category.misc"
        }
    }
}
