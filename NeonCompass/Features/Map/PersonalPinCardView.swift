import SwiftUI

/// La fiche d'une épingle — l'UNIQUE surface du carnet : créer, nommer,
/// annoter, illustrer, cocher, supprimer.
///
/// Elle est unique par choix. L'épingle est posée d'un geste puis nommée ici, ce
/// qui évite une feuille de création qui dirait exactement les mêmes choses. Le
/// titre est donc TOUJOURS éditable — il n'y a pas de mode édition à armer.
///
/// Elle porte la même coquille de verre que `POIDetailView`, et la même croix de
/// 44 pt : sur iPad, le panneau latéral n'a pas d'autre sortie.
struct PersonalPinCardView: View {
    let pin: PersonalPin
    let store: PersonalPinStore
    let onDismiss: () -> Void
    let onDelete: () -> Void

    /// Le titre et la note vivent en LOCAL et ne sont commis qu'à la perte de
    /// focus, à la validation ou à la disparition de la fiche — jamais à la
    /// frappe.
    ///
    /// Le piège est mesuré, et son commentaire est encore dans `MapModel` : taper
    /// un caractère dans le champ de nom d'une épingle coûtait une requête
    /// SwiftData PLUS un filtrage des 537 points, parce que chaque frappe
    /// réévaluait le corps de l'écran. Une écriture par session d'édition, c'est
    /// aussi ce qu'il faut au chantier 2 — `updatedAt` avance une fois, pas
    /// trente.
    @State private var draftTitle: String
    @State private var draftNote: String
    @FocusState private var focusedField: Field?
    @State private var showDeleteConfirmation = false

    private enum Field: Hashable { case title, note }

    init(pin: PersonalPin, store: PersonalPinStore, onDismiss: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.pin = pin
        self.store = store
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _draftTitle = State(initialValue: pin.title)
        _draftNote = State(initialValue: pin.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("map.pins.card.titlePlaceholder", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit(commit)
                Spacer(minLength: 0)
                Button {
                    commit()
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

            iconRow

            TextField("map.pins.card.notePlaceholder", text: $draftNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(NCTypography.body)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .focused($focusedField, equals: .note)

            Button {
                commit()
                store.toggleDone(pin)
            } label: {
                Group {
                    if pin.isDone {
                        Label("map.pins.card.done", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("map.pins.card.markDone", systemImage: "circle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            // Les teintes exactes de « marquer trouvé » sur un POI : le carnet
            // n'invente pas un second vocabulaire pour dire la même chose.
            .tint(pin.isDone ? NCColor.neonCyan : NCColor.sunsetMagenta)

            Button("map.pins.card.delete", systemImage: "trash", role: .destructive) {
                showDeleteConfirmation = true
            }
            .font(.caption)
            .confirmationDialog(
                "map.pins.card.deleteConfirm",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("map.pins.card.delete", role: .destructive) { onDelete() }
                Button("map.pins.card.cancel", role: .cancel) {}
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
        // La fiche vit dans l'arbre de vues et non dans une feuille : elle
        // DISPARAÎT quand la sélection change, et c'est le dernier moment où l'on
        // peut sauver ce qui était en cours de frappe.
        .onDisappear(perform: commit)
        .onChange(of: focusedField) { previous, _ in
            if previous != nil { commit() }
        }
        .task {
            // Une épingle sans nom vient d'être posée : le champ prend le focus et
            // le joueur n'a qu'à taper. Une épingle déjà nommée qu'on rouvre ne
            // fait pas surgir le clavier.
            if pin.title.isEmpty { focusedField = .title }
        }
    }

    private var iconRow: some View {
        HStack(spacing: 8) {
            ForEach(PersonalPinIcon.allCases, id: \.self) { icon in
                Button {
                    store.setIcon(icon, on: pin)
                } label: {
                    Image(systemName: icon.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(icon == pin.iconValue ? NCColor.sunsetOrange : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .overlay(
                            Circle()
                                .strokeBorder(NCColor.sunsetOrange, lineWidth: 2)
                                .opacity(icon == pin.iconValue ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: icon.labelKey)))
                .accessibilityAddTraits(icon == pin.iconValue ? [.isSelected] : [])
            }
        }
    }

    private func commit() {
        store.update(pin, title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), note: draftNote)
    }
}
