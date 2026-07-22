import Testing
@testable import NeonCompass

@MainActor
struct GuidesModelTests {
    private func sampleGuides() -> [Guide] {
        [
            Guide(id: "a", chapter: .beginner, title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil),
                  body: LocalizedText(en: "Body A", fr: nil, es: nil, it: nil, de: nil)),
            Guide(id: "b", chapter: .money, title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil),
                  body: LocalizedText(en: "Body B", fr: nil, es: nil, it: nil, de: nil)),
        ]
    }

    @Test func groupsGuidesByChapter() {
        let model = GuidesModel(guides: sampleGuides())
        #expect(model.guides(in: .beginner).map(\.id) == ["a"])
        #expect(model.guides(in: .money).map(\.id) == ["b"])
        #expect(model.guides(in: .story).isEmpty)
    }

    @Test func updateGuidesReplacesContent() {
        let model = GuidesModel(guides: [])
        #expect(model.guides(in: .beginner).isEmpty)
        model.updateGuides(sampleGuides())
        #expect(model.guides(in: .beginner).map(\.id) == ["a"])
    }
}
