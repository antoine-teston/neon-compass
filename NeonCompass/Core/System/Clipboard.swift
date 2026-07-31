import UIKit

/// Le presse-papiers n'a pas d'équivalent SwiftUI en écriture — `PasteButton`
/// ne fait que coller. C'est l'unique raison pour laquelle UIKit entre dans ce
/// fichier, et il n'entre que par lui.
enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
