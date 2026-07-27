#if DEBUG
import Testing
import Foundation
@testable import NeonCompass

struct EditorDraftTests {
    private static let date = Date(timeIntervalSince1970: 1_763_000_000)

    @Test func createCarriesCategoryAndPosition() {
        let draft = EditorDraft.create(
            id: "u1",
            category: .collectible,
            at: NormalizedPoint(x: 0.25, y: 0.5),
            capturedAt: Self.date
        )
        #expect(draft.kind == .create)
        #expect(draft.category == .collectible)
        #expect(draft.position == NormalizedPoint(x: 0.25, y: 0.5))
        #expect(draft.targetPOIID == nil)
        #expect(draft.title == nil)
    }

    @Test func moveCarriesTargetAndDestination() {
        let draft = EditorDraft.move(
            id: "u2",
            poiID: "poi_leonida_collectible_ab12cd34",
            to: NormalizedPoint(x: 0.1, y: 0.2),
            capturedAt: Self.date
        )
        #expect(draft.kind == .move)
        #expect(draft.targetPOIID == "poi_leonida_collectible_ab12cd34")
        #expect(draft.position == NormalizedPoint(x: 0.1, y: 0.2))
        #expect(draft.category == nil)
    }

    @Test func deleteCarriesTargetOnly() {
        let draft = EditorDraft.delete(id: "u3", poiID: "poi_x", capturedAt: Self.date)
        #expect(draft.kind == .delete)
        #expect(draft.targetPOIID == "poi_x")
        #expect(draft.position == nil)
    }

    /// L'adoption est la passerelle communauté → éditorial : la position et le
    /// titre proposés sont repris tels quels, et l'origine est conservée pour
    /// que `sources` puisse la citer.
    @Test func adoptingACommunitySpotPrefillsEverything() {
        let spot = Contribution(
            id: "c42",
            authorUid: "uid",
            authorHandle: "handle",
            category: .safehouse,
            title: "Planque sous le pont",
            languageCode: "fr",
            position: NormalizedPoint(x: 0.7, y: 0.3),
            status: .approved,
            upvotes: 12,
            downvotes: 0
        )
        let draft = EditorDraft.adopting(spot, id: "u4", capturedAt: Self.date)
        #expect(draft.kind == .create)
        #expect(draft.category == .safehouse)
        #expect(draft.position == NormalizedPoint(x: 0.7, y: 0.3))
        #expect(draft.title == "Planque sous le pont")
        #expect(draft.sourceContributionID == "c42")
    }

    @Test func roundTripsThroughJSON() throws {
        let draft = EditorDraft.create(
            id: "u5",
            category: .vehicle,
            at: NormalizedPoint(x: 0.5, y: 0.5),
            capturedAt: Self.date
        )
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(EditorDraft.self, from: data)
        #expect(decoded == draft)
    }
}
#endif
