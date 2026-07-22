import SwiftUI

struct PersonalPinListSheet: View {
    @Bindable var model: MapModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.personalPins) { pin in
                    Text(pin.title)
                }
                .onDelete { offsets in
                    let pins = model.personalPins
                    for index in offsets {
                        model.deletePersonalPin(pins[index])
                    }
                }
            }
            .navigationTitle(Text("map.personalPins.title"))
        }
    }
}
