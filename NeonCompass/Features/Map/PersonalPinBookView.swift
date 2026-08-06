import SwiftUI

/// Le carnet — la liste des épingles de la carte affichée.
///
/// Ce qu'il apporte et qui manquait le plus : **taper une ligne ramène à
/// l'épingle**. Rien, jusqu'ici, ne permettait de retrouver un repère dont on
/// avait oublié l'emplacement.
///
/// Il ne porte PAS de `NavigationStack` : le CLAUDE.md rappelle qu'un
/// `ToolbarItem` posé sur un écran d'onglet ne s'affiche nulle part, sans erreur
/// ni avertissement. Le titre, le décompte et la fermeture sont donc du contenu.
struct PersonalPinBookView: View {
    let store: PersonalPinStore
    let game: Game
    let isProEntitled: Bool
    let onSelect: (PersonalPin) -> Void
    let onDismiss: () -> Void

    private var pins: [PersonalPin] { store.pins(for: game) }
    private var todo: [PersonalPin] { pins.filter { !$0.isDone } }
    private var done: [PersonalPin] { pins.filter(\.isDone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if pins.isEmpty {
                ContentUnavailableView(
                    "map.pins.empty.title",
                    systemImage: "mappin.slash",
                    description: Text("map.pins.empty.message")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !todo.isEmpty {
                        Section(header: Text("map.pins.section.todo")) {
                            ForEach(todo) { row($0) }
                                .onDelete { delete($0, from: todo) }
                        }
                    }
                    if !done.isEmpty {
                        Section(header: Text("map.pins.section.done")) {
                            ForEach(done) { row($0) }
                                .onDelete { delete($0, from: done) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text("map.personalPins.title")
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)
            Spacer()
            // Le décompte ne s'affiche qu'en gratuit : en Pro il n'y a pas de
            // plafond, donc un dénominateur ne dirait rien.
            if !isProEntitled {
                Text(verbatim: "\(store.pins.count) / \(PersonalPinStore.freeCap)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(store.isAtCap(isProEntitled: false) ? NCColor.sunsetMagenta : .secondary)
                    .accessibilityLabel(Text("map.pins.countAccessibility \(store.pins.count) \(PersonalPinStore.freeCap)"))
            }
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
    }

    private func row(_ pin: PersonalPin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pin.iconValue.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(pin.isDone ? .secondary : NCColor.sunsetOrange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title.isEmpty ? String(localized: "map.pins.untitled") : pin.title)
                    .font(NCTypography.body)
                    .foregroundStyle(pin.isDone ? Color.secondary : Color.white)
                if !pin.note.isEmpty {
                    Text(pin.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                store.toggleDone(pin)
            } label: {
                Image(systemName: pin.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(pin.isDone ? NCColor.neonCyan : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(pin.isDone ? "map.pins.card.done" : "map.pins.card.markDone"))
        }
        .listRowBackground(Color.clear)
        // La ligne ENTIÈRE ramène à l'épingle, sauf la coche qui a sa propre
        // cible. `contentShape` est indispensable : sans elle, l'espace entre le
        // texte et la coche ne recevrait rien.
        .contentShape(.rect)
        .onTapGesture { onSelect(pin) }
    }

    private func delete(_ offsets: IndexSet, from section: [PersonalPin]) {
        for index in offsets { store.delete(section[index]) }
    }
}
