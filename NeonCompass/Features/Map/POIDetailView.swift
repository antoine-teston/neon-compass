import SwiftUI

struct POIDetailView: View {
    let poi: POI
    let isFound: Bool
    let onToggleFound: () -> Void
    let onDismiss: () -> Void
#if DEBUG
    /// Non nil seulement quand le mode éditeur est armé. La fiche est le seul
    /// endroit où agir sur un POI existant : l'appui long sur le vide reste
    /// dédié à la création (règle de geste unique, cf. spec D5).
    var onEditorMove: (() -> Void)?
    var onEditorDelete: (() -> Void)?
    @State private var showDeleteConfirmation = false
#endif

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(poi.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                Spacer()
                // 17 pt en `.secondary` : la seule sortie du panneau iPad était
                // un point gris qu'on ne voyait pas et qu'on manquait. La
                // feuille du compact se balaie, elle pardonnait ; le panneau
                // latéral n'a que ce bouton, il lui faut la cible de 44 pt du
                // HIG. Le retrait négatif la rend grande sans la décoller du
                // coin.
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -10)
                .accessibilityLabel(Text("poi.detail.close"))
            }

            if let note = poi.note {
                // La fiche n'est plus une feuille système : plus personne ne
                // plafonne sa hauteur ni ne la fait défiler à notre place. Or
                // les notes de la fixture vont jusqu'à 819 caractères — un
                // mode d'emploi de cascade — et une fiche haute de tout ça
                // avalerait la carte sur iPhone.
                //
                // `ViewThatFits` prend la première variante qui tient dans la
                // hauteur proposée : la note à sa taille naturelle si elle y
                // tient, la version défilante sinon. La fiche suit donc son
                // texte, et ne se fige qu'une fois le plafond atteint.
                //
                // Le plafond n'est PAS posé ici, et c'est délibéré : un
                // `.frame(maxHeight:)` ne se contente pas de borner, il prend
                // toute la hauteur proposée jusqu'à son maximum et centre son
                // contenu dedans — une note de deux lignes se retrouvait au
                // milieu de 220 pt de vide. C'est l'appelant qui borne, en
                // limitant ce qu'il PROPOSE (voir `MapScreen.detailPanel`).
                ViewThatFits(in: .vertical) {
                    noteText(note)
                    ScrollView { noteText(note) }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }

            Button {
                onToggleFound()
            } label: {
                Group {
                    if isFound {
                        Label("poi.detail.found", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("poi.detail.markFound", systemImage: "circle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(isFound ? NCColor.neonCyan : NCColor.sunsetMagenta)

#if DEBUG
            editorActions
#endif
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    private func noteText(_ note: LocalizedText) -> some View {
        Text(note.resolved(for: currentLanguageCode))
            .font(NCTypography.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

#if DEBUG
    @ViewBuilder
    private var editorActions: some View {
        if onEditorMove != nil || onEditorDelete != nil {
            Divider().overlay(.white.opacity(0.2))
            HStack(spacing: 12) {
                if let onEditorMove {
                    Button("Déplacer", systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: onEditorMove)
                }
                Spacer()
                if onEditorDelete != nil {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .font(.caption)
            .confirmationDialog("Supprimer ce POI ?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { onEditorDelete?() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Un POI déjà publié deviendra une pierre tombale, pas une suppression.")
            }
        }
    }
#endif
}
