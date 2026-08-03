import SwiftUI

struct PersonalPinListSheet: View {
    let store: PersonalPinStore
    let game: Game

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.pins(for: game)) { pin in
                    Text(pin.title)
                }
                .onDelete { offsets in
                    let pins = store.pins(for: game)
                    for index in offsets { store.delete(pins[index]) }
                }
            }
            .navigationTitle(Text("map.personalPins.title"))
        }
    }
}
