# Actu (Feed) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "Actu" tab — the app's default home screen — as a chronological feed of officially-reformulated news (Rockstar announcements, patch/title updates, in-game events), replacing the current `PlaceholderScreen` fallback.

**Architecture:** A new `NewsItem` content type (category + localized title/body + `publishedAt`), synced through the generic `ContentStore<Item>`/`FirestoreContentRepository<Item>` infrastructure built in Plan 3e — no new sync infrastructure needed, this plan is a direct beneficiary of that consolidation. `FeedModel` sorts by `publishedAt` descending; `FeedListView` renders Liquid Glass cards; `FeedScreen` wires the store and replaces the feed tab's placeholder in `RootView`.

**Tech Stack:** SwiftUI + `@Observable`, SwiftData (via the existing generic `ContentStore`), Swift Testing.

## Scope

Per spec §5, the Actu feed conceptually mixes three sources: officially-reformulated news, newly-published POI/guides, and top-voted community spots. This plan builds **only the news source** (`NewsItem`, its own Firestore collection, published editorially through the same content pipeline as POI/Cheat/Guide). The other two sources are explicitly out of scope:
- **Newly-published POI/guides in the feed** — would require adding a `publishedAt` field to the already-shipped `POI`/`Guide` schemas (Plans 2/3c) and merging two additional content streams into `FeedModel`. Deferred to a future plan once there's a concrete need to surface it (the map and Cheats & Guides tabs already surface this content directly).
- **Top-voted community spots** — requires Sign in with Apple, voting, and Cloud Functions, none of which exist yet (Plan 5). Cannot be built before its dependencies.
- **Native sponsored cells / banner ads** — requires AdMob integration (Plan 6). The feed ships without ad slots; they are added when Plan 6 wires up monetization.

## Global Constraints

- Swift 6 strict concurrency; SwiftUI + `@Observable` only; SwiftData for persistence.
- Firebase stays behind `Core/` protocols — this plan adds no new Firebase-importing file; it reuses `FirestoreContentRepository<Item>` (Plan 3e) unchanged.
- Every user-facing string goes through the String Catalog (`Localizable.xcstrings`) — no hardcoded literals.
- `LocalizedText.resolved(for:)` convention: required `en`, optional `fr/es/it/de`, falls back to `en`. Every SwiftUI file displaying localized content declares its own local `currentLanguageCode` computed property (established, deliberately-duplicated-per-file convention — do not extract a shared abstraction).
- Liquid Glass restraint: glow on at most three accents per screen. This plan uses exactly one (`NCColor.neonCyan`), matching the Guides screen's precedent.
- No Rockstar/Take-Two trademarks in any string — news content is always a reformulation, never a verbatim quote of official copy (this is a content-authoring rule enforced by `content-cli check-publishable`, not something this plan's Swift code needs to check itself).
- English-primary today (the French-primary migration is decided but deferred — documented in `CLAUDE.md`, not yet applied). This plan follows the same convention as every prior content-type plan.

---

### Task 1: `NewsItem` model

**Files:**
- Create: `NeonCompass/Core/News/NewsItem.swift`
- Test: `NeonCompassTests/News/NewsItemTests.swift`

**Interfaces:**
- Consumes: `LocalizedText` (`NeonCompass/Core/Map/POI.swift`) — reused as-is.
- Produces: `NewsCategory` (`announcement`/`patch`/`event`), `NewsItem` (`id`, `category`, `title: LocalizedText`, `body: LocalizedText`, `publishedAt: String`). `publishedAt` is a plain ISO-8601 date string (`"YYYY-MM-DD"`), not a `Date` — this keeps the generic `ContentStore`'s `JSONEncoder`/`JSONDecoder` (Plan 3e) free of any date-strategy configuration that would otherwise apply to every content type, not just news. ISO-8601 date strings sort correctly with plain string comparison, which is all `FeedModel` (Task 2) needs.

- [ ] **Step 1: Write the failing test**

Create `NeonCompassTests/News/NewsItemTests.swift`:

```swift
import Testing
import Foundation
@testable import NeonCompass

struct NewsItemTests {
    @Test func decodesNewsItemIgnoringPipelineOnlyFields() throws {
        let json = Data("""
        {
            "id": "news_sample_patch",
            "category": "patch",
            "title": {"en": "Title update 1.1", "fr": "Mise à jour 1.1"},
            "body": {"en": "Sample patch notes, reworded in our own words."},
            "publishedAt": "2026-07-20",
            "status": "draft",
            "sources": ["internal:fixture"]
        }
        """.utf8)
        let newsItem = try JSONDecoder().decode(NewsItem.self, from: json)
        #expect(newsItem.id == "news_sample_patch")
        #expect(newsItem.category == .patch)
        #expect(newsItem.title.resolved(for: "fr") == "Mise à jour 1.1")
        #expect(newsItem.publishedAt == "2026-07-20")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/test.sh` (or, once the project is buildable, filter to `NeonCompassTests/News/NewsItemTests`)
Expected: FAIL — `NewsItem` does not exist yet (compile error).

- [ ] **Step 3: Write the model**

Create `NeonCompass/Core/News/NewsItem.swift`:

```swift
import Foundation

enum NewsCategory: String, CaseIterable, Codable, Sendable {
    case announcement, patch, event
}

struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: NewsCategory
    let title: LocalizedText
    let body: LocalizedText
    let publishedAt: String
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `NewsItemTests` suite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/News/NewsItem.swift NeonCompassTests/News/NewsItemTests.swift
git commit -m "feat: NewsItem model (category, localized title/body, publishedAt)"
```

---

### Task 2: `FeedModel` + `FeedListView`

**Files:**
- Create: `NeonCompass/Features/Feed/FeedModel.swift`
- Create: `NeonCompass/Features/Feed/FeedListView.swift`
- Test: `NeonCompassTests/Feed/FeedModelTests.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `NewsItem`, `NewsCategory` (Task 1).
- Produces: `FeedModel` (`init(newsItems:)`, `private(set) var newsItems: [NewsItem]` sorted most-recent-first, `func updateNewsItems(_ newItems: [NewsItem])`), `FeedListView` (`@Bindable var model: FeedModel`, no other parameters — no navigation/detail view exists for news items in this plan, cards show the full body inline since news items are short by nature, unlike guides).

- [ ] **Step 1: Write the failing tests**

Create `NeonCompassTests/Feed/FeedModelTests.swift`:

```swift
import Testing
@testable import NeonCompass

@MainActor
struct FeedModelTests {
    private func sampleItem(id: String, publishedAt: String) -> NewsItem {
        NewsItem(
            id: id,
            category: .announcement,
            title: LocalizedText(en: "Title \(id)", fr: nil, es: nil, it: nil, de: nil),
            body: LocalizedText(en: "Body \(id)", fr: nil, es: nil, it: nil, de: nil),
            publishedAt: publishedAt
        )
    }

    @Test func sortsNewsItemsByMostRecentFirst() {
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        let model = FeedModel(newsItems: [older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }

    @Test func updateNewsItemsReplacesContentAndResorts() {
        let model = FeedModel(newsItems: [])
        let older = sampleItem(id: "a", publishedAt: "2026-07-01")
        let newer = sampleItem(id: "b", publishedAt: "2026-07-20")
        model.updateNewsItems([older, newer])
        #expect(model.newsItems.map(\.id) == ["b", "a"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Scripts/test.sh`
Expected: FAIL — `FeedModel` does not exist yet (compile error).

- [ ] **Step 3: Write `FeedModel`**

Create `NeonCompass/Features/Feed/FeedModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class FeedModel {
    private(set) var newsItems: [NewsItem]

    init(newsItems: [NewsItem]) {
        self.newsItems = Self.sortedByMostRecent(newsItems)
    }

    func updateNewsItems(_ newItems: [NewsItem]) {
        newsItems = Self.sortedByMostRecent(newItems)
    }

    private static func sortedByMostRecent(_ items: [NewsItem]) -> [NewsItem] {
        items.sorted { $0.publishedAt > $1.publishedAt }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `FeedModelTests` suite (still FAIL on `FeedListView`'s file not existing yet only if something else references it — it does not, so this step should already pass once `FeedModel` compiles).

- [ ] **Step 5: Add the feed's String Catalog keys**

In `Localizable.xcstrings`, add 4 new keys following the existing structure used by the `guides.chapter.*` keys (Plan 3c):
- `feed.empty` = "No news yet — check back soon."
- `feed.category.announcement` = "Announcement"
- `feed.category.patch` = "Patch"
- `feed.category.event` = "Event"

- [ ] **Step 6: Write `FeedListView`**

Create `NeonCompass/Features/Feed/FeedListView.swift`:

```swift
import SwiftUI

struct FeedListView: View {
    @Bindable var model: FeedModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.newsItems.isEmpty {
                    emptyState
                } else {
                    ForEach(model.newsItems) { item in
                        card(for: item)
                    }
                }
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func card(for item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(categoryTitleKey(item.category), systemImage: categorySymbol(item.category))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            Text(item.title.resolved(for: currentLanguageCode))
                .font(NCTypography.displayTitle)
                .foregroundStyle(.white)

            Text(item.body.resolved(for: currentLanguageCode))
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.system(size: 32))
                .foregroundStyle(NCColor.neonCyan)
            Text("feed.empty")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private func categoryTitleKey(_ category: NewsCategory) -> LocalizedStringKey {
        switch category {
        case .announcement: "feed.category.announcement"
        case .patch: "feed.category.patch"
        case .event: "feed.category.event"
        }
    }

    private func categorySymbol(_ category: NewsCategory) -> String {
        switch category {
        case .announcement: "megaphone"
        case .patch: "wrench.and.screwdriver"
        case .event: "calendar"
        }
    }
}
```

- [ ] **Step 7: Build to verify `FeedListView` compiles**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (nothing references `FeedListView` yet, so this only verifies it compiles in isolation).

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Features/Feed/FeedModel.swift NeonCompass/Features/Feed/FeedListView.swift NeonCompassTests/Feed/FeedModelTests.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: FeedModel (chronological sort) + FeedListView (Liquid Glass cards, category glyphs)"
```

---

### Task 3: `FeedScreen` — wire the generic store, integrate into `RootView`

**Files:**
- Create: `NeonCompass/Features/Feed/FeedScreen.swift`
- Modify: `NeonCompass/App/RootView.swift`

**Interfaces:**
- Consumes: `ContentStore<Item>`, `FirestoreContentRepository<Item>` (Plan 3e, already merged — no changes needed to either), `RemoteConfigVersionProvider` (existing), `FeedModel`/`FeedListView` (Task 2).
- Produces: `FeedScreen` — the `AppTab.feed` case's real screen, replacing `PlaceholderScreen(tab: .feed)`.

No new unit test — assembly of already-tested pieces (`FeedModel` tested in Task 2, `ContentStore<Item>` tested generically in Plan 3e), same convention as `CheatsScreen`/`MapScreen`. Verification is build + visual check on simulator (iPhone and iPad).

- [ ] **Step 1: Write `FeedScreen`**

Create `NeonCompass/Features/Feed/FeedScreen.swift`:

```swift
import SwiftUI
import SwiftData

struct FeedScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: FeedModel?

    var body: some View {
        Group {
            if let model {
                FeedListView(model: model)
            } else {
                ProgressView()
                    .task { await loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<NewsItem>(
            collectionName: "news",
            remote: FirestoreContentRepository<NewsItem>(collectionName: "news"),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = FeedModel(newsItems: contentStore.items)
        try? await contentStore.syncIfNeeded()
        model?.updateNewsItems(contentStore.items)
    }
}
```

- [ ] **Step 2: Wire `FeedScreen` into `RootView`**

In `NeonCompass/App/RootView.swift`, the `screen(for:)` method currently reads:

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
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
        default: PlaceholderScreen(tab: tab)
        }
    }
```

(`.progress` and `.profile` still fall through to `PlaceholderScreen` — unrelated to this plan, built in later roadmap plans.)

- [ ] **Step 3: Build and run the full test suite**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Visual verification**

Launch the simulator (iPhone and iPad). Confirm: the Actu tab (default tab on launch) shows the feed instead of the placeholder; empty state ("No news yet...") displays correctly since no news content has been published to Firestore yet; no regression on the Cheats & Guides or Map tabs.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Feed/FeedScreen.swift NeonCompass/App/RootView.swift
git commit -m "feat: wire FeedScreen into the Actu tab (default home screen)"
```

---

## Self-Review

**Couverture spec** : source "actualités officielles reformulées" du feed Actu (spec §5) couverte de bout en bout — modèle, tri chronologique, rendu, intégration dans l'onglet par défaut. Les deux autres sources (POI/guides récents, spots communautaires votés) et les cellules sponsorisées sont explicitement hors scope (section Scope ci-dessus), chacune bloquée sur une dépendance non construite (schema POI/Guide sans `publishedAt`, ou Plans 5/6).

**Bénéfice direct de la consolidation (Plan 3e)** : ce plan n'a besoin d'aucune tâche "infrastructure de sync" — contrairement aux Plans 3b/3c qui devaient chacun construire leur propre `ContentStore`/`CacheEntry`/`RemoteRepository`, celui-ci réutilise directement `ContentStore<NewsItem>`/`FirestoreContentRepository<NewsItem>` (3 tâches au lieu de 4, la 4ᵉ collection de contenu sans aucune duplication).

**Cohérence des types** : `NewsItem`/`NewsCategory` (Task 1) réutilisés tels quels dans `FeedModel`/`FeedListView` (Task 2) et `FeedScreen` (Task 3).

**Localisation** : `FeedListView` utilise `resolved(for: currentLanguageCode)` dès l'écriture initiale pour `title`/`body`, pas de correctif après coup — leçon des plans précédents appliquée directement.

**Dette signalée pour un plan futur (pas de ce plan)** :
1. Sources feed manquantes (POI/guides récents, spots communautaires) — à réévaluer une fois leurs dépendances construites.
2. Cellules sponsorisées natives + bannière — Plan 6 (monétisation).
3. Migration français-primaire — toujours documentée seulement (CLAUDE.md), non appliquée.
4. Nit du Plan 3e (non bloquant) : `collectionName` passé comme deux littéraux indépendants (`ContentStore` + `FirestoreContentRepository`) à chaque site d'appel, y compris celui ajouté par ce plan (`"news"` répété deux fois dans `FeedScreen.loadModel()`) — même remarque que pour POI/Cheats/Guides, à resserrer si un futur refactor de l'API le justifie.
