import Foundation
import Observation

@Observable
@MainActor
final class GuidesModel {
    private(set) var guides: [Guide]

    init(guides: [Guide]) {
        self.guides = guides
    }

    func updateGuides(_ newGuides: [Guide]) {
        guides = newGuides
    }

    func guides(in chapter: GuideChapter) -> [Guide] {
        guides.filter { $0.chapter == chapter }
    }
}
