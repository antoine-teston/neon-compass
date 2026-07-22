import Foundation
import SwiftData

@Model
final class FavoriteCheat {
    @Attribute(.unique) var cheatID: String

    init(cheatID: String) {
        self.cheatID = cheatID
    }
}
