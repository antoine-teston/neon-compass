# Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Progression" tab: auto-generated POI checklists (global + per-category percentages, neon progress ring) sourced from the same SwiftData `FoundEntry` table the map already writes to, plus a manually-checked trophy checklist (v1 has no PSN/Xbox integration — trophies are a freely-reproducible fact, checked off by hand).

**Architecture:** Fixes a real, previously-deferred reactivity gap first (Task 1) — `MapModel.isFound`/`CheatsModel.isFavorite` re-query SwiftData from scratch on every call instead of reading an `@Observable`-tracked stored property, so SwiftUI has no signal to re-render views when `toggleFound`/`toggleFavorite` runs. This was explicitly flagged across Plans 2/3b/3c/3e as "fix together, at Plan 4 planning time, since Progression's checklists will read this same state" — that time is now. Then: a new `Trophy` content type + `TrophyProgress` SwiftData model (mirrors the established `Guide`/`FavoriteCheat` pattern), a `ProgressionModel` computing percentages from `POI`/`FoundEntry` and exposing the trophy toggle, a reusable `ProgressRing` design-system component, and `ProgressionScreen` wiring it all together via the generic `ContentStore<Item>` (Plan 3e) — replacing the Progression tab's placeholder.

**Tech Stack:** SwiftUI + `@Observable`, SwiftData, Swift Testing. No new Firebase surface — reuses `FirestoreContentRepository<Item>`/`ContentStore<Item>` unchanged.

## Global Constraints

- Swift 6 strict concurrency; SwiftUI + `@Observable` only; SwiftData for persistence.
- `FoundEntry` (`NeonCompass/Core/Map/FoundEntry.swift`) is the single source of truth for POI "found" state, shared between the map and Progression — this plan reads it, never duplicates it into a second table.
- Every user-facing string goes through the String Catalog — no hardcoded literals. Category labels reuse `POICategory.localizedNameKey` (already defined, already localized in `POI.swift`) rather than inventing new keys.
- `LocalizedText.resolved(for:)` convention with the established per-file `currentLanguageCode` duplication (not a defect).
- Liquid Glass restraint: glow on at most three accents per screen. This plan's Progression screen uses exactly one (`NCColor.neonCyan`), matching the Guides/Feed precedent.
- No Rockstar/Take-Two trademarks — trophy content, once real trophies exist, follows the same reformulation rule as everything else (content-authoring concern, not this plan's Swift code).
- English-primary today (French-primary migration decided but deferred, documented in CLAUDE.md only).
- Pre-launch codebase — no SwiftData migration concerns for the new `TrophyProgress` model.

---

### Task 1: Fix found/favorite reactivity (`MapModel`, `CheatsModel`)

**Files:**
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsModel.swift`
- Modify: `NeonCompassTests/Map/MapModelTests.swift`
- Modify: `NeonCompassTests/Cheats/CheatsModelTests.swift`

**Interfaces:**
- Produces: `MapModel.foundPOIIDs: Set<String>` (new, `private(set)`), `CheatsModel.favoriteCheatIDs: Set<String>` (new, `private(set)`). `isFound(_:)`/`isFavorite(_:)`/`toggleFound(_:)`/`toggleFavorite(_:)` keep their exact existing signatures — no call site anywhere in the app changes; only their internal implementation does. This is the point: fixing the bug requires zero changes to any consuming view.

Why this is a real bug, not a style preference: `isFound(_:)` currently does a fresh `modelContext.fetchCount` on every call — a plain method call, not a stored-property read. SwiftUI's `@Observable` macro only tracks *stored property* access for view-invalidation purposes; a method that queries SwiftData internally gives it nothing to track. `toggleFound(_:)` mutates zero stored properties on `MapModel` today, so after calling it, no SwiftUI view that displayed `model.isFound(poi)` is told to re-render — the checkmark/found-state visible on screen can go stale until something unrelated forces a re-render. Moving the read to a stored `Set<String>` that `toggleFound`/`toggleFavorite` mutate directly fixes this: `@Observable` now has a real property to track, so any view reading `isFound`/`isFavorite` (which read `foundPOIIDs`/`favoriteCheatIDs` internally) is correctly invalidated the instant the set changes.

A unit test cannot observe "did SwiftUI re-render" directly, but it CAN prove the property this plan introduces exists, is populated correctly at init, and updates immediately on toggle — which is the testable half of the contract (the other half, "an `@Observable`-tracked property change invalidates dependent view bodies," is a SwiftUI framework guarantee, not something this plan needs to re-prove).

- [ ] **Step 1: Write the failing tests**

In `NeonCompassTests/Map/MapModelTests.swift`, add this test (keep all existing tests unchanged):

```swift
    @Test func foundPOIIDsReflectsToggleImmediately() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let poi = samplePOIs()[0]
        #expect(!model.foundPOIIDs.contains(poi.id))
        model.toggleFound(poi)
        #expect(model.foundPOIIDs.contains(poi.id))
        model.toggleFound(poi)
        #expect(!model.foundPOIIDs.contains(poi.id))
    }
```

In `NeonCompassTests/Cheats/CheatsModelTests.swift`, add this test (keep all existing tests unchanged):

```swift
    @Test func favoriteCheatIDsReflectsToggleImmediately() {
        let model = CheatsModel(cheats: sampleCheats(), modelContext: makeContext(), defaults: freshDefaults())
        let cheat = sampleCheats()[0]
        #expect(!model.favoriteCheatIDs.contains(cheat.id))
        model.toggleFavorite(cheat)
        #expect(model.favoriteCheatIDs.contains(cheat.id))
        model.toggleFavorite(cheat)
        #expect(!model.favoriteCheatIDs.contains(cheat.id))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Scripts/test.sh`
Expected: both new tests FAIL to compile — `foundPOIIDs`/`favoriteCheatIDs` do not exist yet.

- [ ] **Step 3: Fix `MapModel`**

In `NeonCompass/Features/Map/MapModel.swift`, change:

```swift
@Observable
@MainActor
final class MapModel {
    private(set) var pois: [POI]
    var activeCategories: Set<POICategory>
    var searchQuery: String = ""
    var selectedPOI: POI?

    private let modelContext: ModelContext

    init(pois: [POI], modelContext: ModelContext) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
    }
```

to:

```swift
@Observable
@MainActor
final class MapModel {
    private(set) var pois: [POI]
    var activeCategories: Set<POICategory>
    var searchQuery: String = ""
    var selectedPOI: POI?
    private(set) var foundPOIIDs: Set<String>

    private let modelContext: ModelContext

    init(pois: [POI], modelContext: ModelContext) {
        self.pois = pois
        self.activeCategories = Set(POICategory.allCases)
        self.modelContext = modelContext
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
    }
```

Then change:

```swift
    func isFound(_ poi: POI) -> Bool {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id))
        }
        try? modelContext.save()
    }
```

to:

```swift
    func isFound(_ poi: POI) -> Bool {
        foundPOIIDs.contains(poi.id)
    }

    func toggleFound(_ poi: POI) {
        let poiID = poi.id
        let descriptor = FetchDescriptor<FoundEntry>(predicate: #Predicate { $0.poiID == poiID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            foundPOIIDs.remove(poiID)
        } else {
            modelContext.insert(FoundEntry(poiID: poi.id))
            foundPOIIDs.insert(poiID)
        }
        try? modelContext.save()
    }
```

- [ ] **Step 4: Fix `CheatsModel`**

In `NeonCompass/Features/Cheats/CheatsModel.swift`, change:

```swift
    private(set) var cheats: [Cheat]
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>
```

to:

```swift
    private(set) var cheats: [Cheat]
    var searchQuery: String = ""
    var activeCategories: Set<CheatCategory>
    private(set) var favoriteCheatIDs: Set<String>
```

Then change the `init` body from:

```swift
    init(cheats: [Cheat], modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.activeCategories = Set(CheatCategory.allCases)
        let stored = defaults.string(forKey: Self.platformKey).flatMap(Platform.init(rawValue:))
        self.activePlatform = stored ?? .ps5
    }
```

to:

```swift
    init(cheats: [Cheat], modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.cheats = cheats
        self.modelContext = modelContext
        self.defaults = defaults
        self.activeCategories = Set(CheatCategory.allCases)
        self.favoriteCheatIDs = Set((try? modelContext.fetch(FetchDescriptor<FavoriteCheat>()))?.map(\.cheatID) ?? [])
        let stored = defaults.string(forKey: Self.platformKey).flatMap(Platform.init(rawValue:))
        self.activePlatform = stored ?? .ps5
    }
```

Then change:

```swift
    func isFavorite(_ cheat: Cheat) -> Bool {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
        }
        try? modelContext.save()
    }
```

to:

```swift
    func isFavorite(_ cheat: Cheat) -> Bool {
        favoriteCheatIDs.contains(cheat.id)
    }

    func toggleFavorite(_ cheat: Cheat) {
        let cheatID = cheat.id
        let descriptor = FetchDescriptor<FavoriteCheat>(predicate: #Predicate { $0.cheatID == cheatID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            favoriteCheatIDs.remove(cheatID)
        } else {
            modelContext.insert(FavoriteCheat(cheatID: cheat.id))
            favoriteCheatIDs.insert(cheatID)
        }
        try? modelContext.save()
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including both new tests. All pre-existing `MapModelTests`/`CheatsModelTests` tests still pass unchanged (the public behavior of `isFound`/`isFavorite`/`toggleFound`/`toggleFavorite` is identical — only its internal wiring to `@Observable` changed).

- [ ] **Step 6: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Map/MapModel.swift NeonCompass/Features/Cheats/CheatsModel.swift NeonCompassTests/Map/MapModelTests.swift NeonCompassTests/Cheats/CheatsModelTests.swift
git commit -m "fix: found/favorite state as observable-tracked Sets, fixing stale UI after toggle"
```

---

### Task 2: `Trophy` content model + `TrophyProgress`

**Files:**
- Create: `NeonCompass/Core/Progression/Trophy.swift`
- Create: `NeonCompass/Core/Progression/TrophyProgress.swift`
- Test: `NeonCompassTests/Progression/TrophyTests.swift`

**Interfaces:**
- Consumes: `LocalizedText` (`NeonCompass/Core/Map/POI.swift`) — reused as-is.
- Produces: `Trophy` (`id`, `title: LocalizedText`, `note: LocalizedText?`, `Codable, Equatable, Identifiable, Sendable`), `TrophyProgress` (SwiftData `@Model`, `@Attribute(.unique) var trophyID: String`).

- [ ] **Step 1: Write the failing test**

Create `NeonCompassTests/Progression/TrophyTests.swift`:

```swift
import Testing
import Foundation
@testable import NeonCompass

struct TrophyTests {
    @Test func decodesTrophyIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "trophy_sample_completionist",
            "title": {"en": "Sample Completionist", "fr": "Complétiste (exemple)"},
            "note": {"en": "Sample trophy fixture, not a confirmed GTA VI trophy."},
            "status": "draft",
            "sources": ["internal:fixture"]
        }
        """.utf8)
        let trophy = try JSONDecoder().decode(Trophy.self, from: json)
        #expect(trophy.id == "trophy_sample_completionist")
        #expect(trophy.title.resolved(for: "fr") == "Complétiste (exemple)")
        #expect(trophy.note?.en.contains("Sample trophy") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/test.sh`
Expected: FAIL — `Trophy` does not exist yet (compile error).

- [ ] **Step 3: Write the models**

Create `NeonCompass/Core/Progression/Trophy.swift`:

```swift
import Foundation

struct Trophy: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: LocalizedText
    let note: LocalizedText?
}
```

Create `NeonCompass/Core/Progression/TrophyProgress.swift`:

```swift
import Foundation
import SwiftData

/// Suivi manuel des trophées (spec §5 : « checklists manuelles » — v1 n'a
/// aucune intégration PSN/Xbox ; l'utilisateur coche lui-même).
@Model
final class TrophyProgress {
    @Attribute(.unique) var trophyID: String

    init(trophyID: String) {
        self.trophyID = trophyID
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `TrophyTests` suite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Progression/Trophy.swift NeonCompass/Core/Progression/TrophyProgress.swift NeonCompassTests/Progression/TrophyTests.swift
git commit -m "feat: Trophy model + TrophyProgress (manual trophy checklist storage)"
```

---

### Task 3: `ProgressionModel`

**Files:**
- Create: `NeonCompass/Features/Progression/ProgressionModel.swift`
- Test: `NeonCompassTests/Progression/ProgressionModelTests.swift`

**Interfaces:**
- Consumes: `POI`, `POICategory` (`Core/Map/POI.swift`), `FoundEntry` (`Core/Map/FoundEntry.swift`), `Trophy`, `TrophyProgress` (Task 2).
- Produces: `ProgressionModel` (`init(pois:trophies:modelContext:)`, `private(set) var pois: [POI]`, `private(set) var trophies: [Trophy]`, `func updatePOIs(_ newPOIs: [POI])`, `func updateTrophies(_ newTrophies: [Trophy])`, `var overallProgress: Double` (0...1, found POI ÷ total POI, `0` if `pois` is empty), `func progress(in category: POICategory) -> Double` (found ÷ total within that category, `0` if none), `func isTrophyChecked(_ trophy: Trophy) -> Bool`, `func toggleTrophy(_ trophy: Trophy)`). POI found-state here is read-only (toggling "Trouvé" stays the map's job, per spec — Progression is a dashboard); trophy checking is this screen's own responsibility, since there is no other home for it.

- [ ] **Step 1: Write the failing tests**

Create `NeonCompassTests/Progression/ProgressionModelTests.swift`:

```swift
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct ProgressionModelTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, TrophyProgress.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOIs() -> [POI] {
        [
            POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "b", category: .landmark, position: NormalizedPoint(x: 0.2, y: 0.2),
                title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "c", category: .collectible, position: NormalizedPoint(x: 0.3, y: 0.3),
                title: LocalizedText(en: "Gamma", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ]
    }

    private func sampleTrophy(id: String) -> Trophy {
        Trophy(id: id, title: LocalizedText(en: "Trophy \(id)", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func overallProgressReflectsFoundEntries() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = ProgressionModel(pois: samplePOIs(), trophies: [], modelContext: context)
        #expect(abs(model.overallProgress - (1.0 / 3.0)) < 0.0001)
    }

    @Test func overallProgressIsZeroWithNoPOIs() {
        let model = ProgressionModel(pois: [], trophies: [], modelContext: makeContext())
        #expect(model.overallProgress == 0)
    }

    @Test func progressInCategoryIsScopedToThatCategory() {
        let context = makeContext()
        context.insert(FoundEntry(poiID: "a"))
        let model = ProgressionModel(pois: samplePOIs(), trophies: [], modelContext: context)
        #expect(abs(model.progress(in: .landmark) - 0.5) < 0.0001)
        #expect(model.progress(in: .collectible) == 0)
    }

    @Test func toggleTrophyPersistsAndIsIdempotent() {
        let trophy = sampleTrophy(id: "t1")
        let model = ProgressionModel(pois: [], trophies: [trophy], modelContext: makeContext())
        #expect(!model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(model.isTrophyChecked(trophy))
        model.toggleTrophy(trophy)
        #expect(!model.isTrophyChecked(trophy))
    }

    @Test func updatePOIsAndUpdateTrophiesReplaceContent() {
        let model = ProgressionModel(pois: [], trophies: [], modelContext: makeContext())
        model.updatePOIs(samplePOIs())
        model.updateTrophies([sampleTrophy(id: "t1")])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
        #expect(model.trophies.map(\.id) == ["t1"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Scripts/test.sh`
Expected: FAIL — `ProgressionModel` does not exist yet (compile error).

- [ ] **Step 3: Write `ProgressionModel`**

Create `NeonCompass/Features/Progression/ProgressionModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ProgressionModel {
    private(set) var pois: [POI]
    private(set) var trophies: [Trophy]
    private(set) var checkedTrophyIDs: Set<String>

    private let foundPOIIDs: Set<String>
    private let modelContext: ModelContext

    init(pois: [POI], trophies: [Trophy], modelContext: ModelContext) {
        self.pois = pois
        self.trophies = trophies
        self.modelContext = modelContext
        self.foundPOIIDs = Set((try? modelContext.fetch(FetchDescriptor<FoundEntry>()))?.map(\.poiID) ?? [])
        self.checkedTrophyIDs = Set((try? modelContext.fetch(FetchDescriptor<TrophyProgress>()))?.map(\.trophyID) ?? [])
    }

    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
    }

    func updateTrophies(_ newTrophies: [Trophy]) {
        trophies = newTrophies
    }

    var overallProgress: Double {
        guard !pois.isEmpty else { return 0 }
        return Double(pois.filter { foundPOIIDs.contains($0.id) }.count) / Double(pois.count)
    }

    func progress(in category: POICategory) -> Double {
        let categoryPOIs = pois.filter { $0.category == category }
        guard !categoryPOIs.isEmpty else { return 0 }
        let foundCount = categoryPOIs.filter { foundPOIIDs.contains($0.id) }.count
        return Double(foundCount) / Double(categoryPOIs.count)
    }

    func isTrophyChecked(_ trophy: Trophy) -> Bool {
        checkedTrophyIDs.contains(trophy.id)
    }

    func toggleTrophy(_ trophy: Trophy) {
        let trophyID = trophy.id
        let descriptor = FetchDescriptor<TrophyProgress>(predicate: #Predicate { $0.trophyID == trophyID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            checkedTrophyIDs.remove(trophyID)
        } else {
            modelContext.insert(TrophyProgress(trophyID: trophyID))
            checkedTrophyIDs.insert(trophyID)
        }
        try? modelContext.save()
    }
}
```

Note: `foundPOIIDs` here is deliberately `let`, not `var` like Task 1's `MapModel.foundPOIIDs` — Progression never mutates it (POI found-state is toggled only from the map), so it's populated once at `init` and read-only for this model's lifetime. Since `ProgressionScreen` (Task 5) reconstructs `ProgressionModel` fresh every time the Progression tab becomes visible (matching the existing `CheatsScreen`/`GuidesModel`/`FeedScreen` pattern — `@State` resets when a tab's view leaves the hierarchy), this always reflects the latest `FoundEntry` state on each visit without needing live cross-model synchronization with `MapModel`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `ProgressionModelTests` suite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Progression/ProgressionModel.swift NeonCompassTests/Progression/ProgressionModelTests.swift
git commit -m "feat: ProgressionModel (POI completion percentages, manual trophy toggle)"
```

---

### Task 4: `ProgressRing` + `ProgressionListView`

**Files:**
- Create: `NeonCompass/Core/DesignSystem/ProgressRing.swift`
- Create: `NeonCompass/Features/Progression/ProgressionListView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ProgressionModel` (Task 3), `POICategory.localizedNameKey` (existing, `Core/Map/POI.swift` — reused, not duplicated), `Trophy` (Task 2).
- Produces: `ProgressRing` (`let progress: Double`, `var lineWidth: CGFloat = 10`), `ProgressionListView` (`@Bindable var model: ProgressionModel`).

No unit test for this task — both are pure SwiftUI view assembly over already-tested data (`ProgressionModel`, Task 3), matching the established `CheatsListView`/`GuidesListView`/`FeedListView` convention. Verification is build + visual check on simulator (iPhone and iPad).

- [ ] **Step 1: Write `ProgressRing`**

Create `NeonCompass/Core/DesignSystem/ProgressRing.swift`:

```swift
import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(NCColor.neonCyan, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: NCColor.neonCyan.opacity(0.6), radius: 6)
            Text("\(Int((progress * 100).rounded()))%")
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 2: Add the Progression screen's String Catalog keys**

In `Localizable.xcstrings`, add 2 new keys following the existing structure used by the `feed.category.*` keys (Plan 3d):
- `progress.trophies.title` = "Trophies"
- `progress.trophies.empty` = "No trophies published yet — check back closer to launch."

- [ ] **Step 3: Write `ProgressionListView`**

Create `NeonCompass/Features/Progression/ProgressionListView.swift`:

```swift
import SwiftUI

struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProgressRing(progress: model.overallProgress)
                    .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(POICategory.allCases, id: \.self) { category in
                        categoryRow(category)
                    }
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                trophySection
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func categoryRow(_ category: POICategory) -> some View {
        HStack {
            Text(category.localizedNameKey)
                .font(NCTypography.body)
                .foregroundStyle(.white)
            Spacer()
            Text("\(Int((model.progress(in: category) * 100).rounded()))%")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var trophySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("progress.trophies.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if model.trophies.isEmpty {
                Text("progress.trophies.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(model.trophies) { trophy in
                    trophyRow(trophy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trophyRow(_ trophy: Trophy) -> some View {
        Button {
            model.toggleTrophy(trophy)
        } label: {
            HStack {
                Image(systemName: model.isTrophyChecked(trophy) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isTrophyChecked(trophy) ? NCColor.neonCyan : .white.opacity(0.4))
                Text(trophy.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
```

- [ ] **Step 4: Build to verify both views compile**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (nothing references `ProgressionListView`/`ProgressRing` yet, so this only verifies they compile in isolation).

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/DesignSystem/ProgressRing.swift NeonCompass/Features/Progression/ProgressionListView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: ProgressRing (neon glow accent) + ProgressionListView (category breakdown, trophy checklist)"
```

---

### Task 5: `ProgressionScreen` — wire the generic store, integrate into `RootView`

**Files:**
- Create: `NeonCompass/Features/Progression/ProgressionScreen.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`

**Interfaces:**
- Consumes: `ContentStore<Item>`, `FirestoreContentRepository<Item>` (Plan 3e, unchanged), `RemoteConfigVersionProvider` (existing), `ProgressionModel`/`ProgressionListView` (Tasks 3-4).
- Produces: `ProgressionScreen` — the `AppTab.progress` case's real screen, replacing `PlaceholderScreen(tab: .progress)`.

No new unit test — assembly of already-tested pieces, same convention as `CheatsScreen`/`FeedScreen`. Verification is build + visual check on simulator (iPhone and iPad).

- [ ] **Step 1: Write `ProgressionScreen`**

Create `NeonCompass/Features/Progression/ProgressionScreen.swift`:

```swift
import SwiftUI
import SwiftData

struct ProgressionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: ProgressionModel?

    var body: some View {
        Group {
            if let model {
                ProgressionListView(model: model)
            } else {
                ProgressView()
                    .task { await loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let poiStore = ContentStore<POI>(
            collectionName: "poi",
            remote: FirestoreContentRepository<POI>(collectionName: "poi"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        let trophyStore = ContentStore<Trophy>(
            collectionName: "trophies",
            remote: FirestoreContentRepository<Trophy>(collectionName: "trophies"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = ProgressionModel(pois: poiStore.items, trophies: trophyStore.items, modelContext: modelContext)
        try? await poiStore.syncIfNeeded()
        try? await trophyStore.syncIfNeeded()
        model?.updatePOIs(poiStore.items)
        model?.updateTrophies(trophyStore.items)
    }
}
```

- [ ] **Step 2: Register `TrophyProgress` in the app's model container**

In `NeonCompass/App/NeonCompassApp.swift`, change:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self])
```

to:

```swift
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, FavoriteCheat.self, ContentCacheEntry.self, TrophyProgress.self])
```

- [ ] **Step 3: Wire `ProgressionScreen` into `RootView`**

In `NeonCompass/App/RootView.swift`, the `screen(for:)` method currently reads (after Plan 3d's change):

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        default: PlaceholderScreen(tab: tab)
        }
    }
```

Change it to:

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .progress: ProgressionScreen()
        default: PlaceholderScreen(tab: tab)
        }
    }
```

(`.profile` still falls through to `PlaceholderScreen` — built in a later roadmap plan.)

- [ ] **Step 4: Build and run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Visual verification**

Launch the simulator (iPhone and iPad). Confirm: the Progression tab shows the ring + category breakdown + trophy section instead of the placeholder; toggling "Trouvé" on a POI in the Map tab, then switching to Progression, shows the updated percentage (this also indirectly confirms Task 1's fix — the map's own "Trouvé" button/badge should now update immediately without needing to leave and re-enter the POI detail sheet); trophy section shows the empty state (no trophy content published yet); no regression on Feed/Map/Cheats & Guides tabs.

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/Features/Progression/ProgressionScreen.swift NeonCompass/App/RootView.swift NeonCompass/App/NeonCompassApp.swift
git commit -m "feat: wire ProgressionScreen into the Progression tab"
```

---

## Self-Review

**Couverture spec** : checklists auto-générées depuis le contenu ✓, pourcentages global et par catégorie ✓, anneau de progression néon ✓, même enregistrement SwiftData que le « Trouvé » de la carte (`FoundEntry`, aucune duplication) ✓, checklists manuelles pour les trophées (pas d'intégration PSN/Xbox v1) ✓.

**Dette payée** : le bug de réactivité found/favori, explicitement reporté à ce plan depuis les Plans 2/3b/3c/3e, est corrigé en Task 1 avant toute nouvelle feature — condition nécessaire pour que Progression affiche des pourcentages fiables, et corrige au passage l'expérience carte/cheats existante (badges qui restaient périmés après un toggle).

**Cohérence des types** : `Trophy`/`TrophyProgress` (Task 2) réutilisés tels quels dans `ProgressionModel` (Task 3), `ProgressionListView` (Task 4), `ProgressionScreen` (Task 5). `POI`/`POICategory`/`FoundEntry` réutilisés sans modification.

**Bénéfice de la consolidation (Plan 3e)** : comme le Plan 3d, ce plan n'ajoute aucune infrastructure de sync — `ContentStore<Trophy>`/`FirestoreContentRepository<Trophy>` réutilisent directement le générique existant, 4ᵉ type de contenu sans duplication (Trophy rejoint POI/Cheat/Guide/News).

**Ce que ce plan ne fait pas (volontairement)** :
1. Pas de bascule "Trouvé" depuis Progression elle-même — reste une action de la carte, Progression est un tableau de bord en lecture seule pour les POI (les trophées, eux, sont bien cochables depuis Progression puisqu'ils n'ont pas d'autre écran).
2. Les POI sans position (Plan 3f) comptent dans les pourcentages au même titre que les autres — un utilisateur ne peut pas encore les marquer "Trouvé" tant qu'ils n'ont pas de coordonnées (pas de pin à taper sur la carte), donc leur present dans le dénominateur peut légèrement sous-estimer l'atteignable réel à court terme. Pas un bug : une fois leur position confirmée, ils redeviennent normalement complétables sans aucun changement de code. À revisiter seulement si ça devient un problème concret (ex. beaucoup de POI restent longtemps sans position).
3. Pas de contenu trophée réel — le jeu n'étant pas encore sorti, la liste officielle des trophées n'existe pas ; l'écran affiche son état vide tant que rien n'est publié (même précédent que Guides/Feed avant leur premier contenu).
4. Migration français-primaire — toujours documentée seulement (CLAUDE.md), non appliquée.
5. Nit des Plans 3e/3d (non bloquant) : `collectionName` dupliqué en 2 littéraux indépendants par site d'appel, y compris `"trophies"` dans ce plan — même remarque, à resserrer si un futur refactor le justifie.
