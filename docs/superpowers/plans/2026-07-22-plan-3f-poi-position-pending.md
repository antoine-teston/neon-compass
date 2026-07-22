# POI Position-Pending Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a real content/model mismatch surfaced by this week's first content-pipeline batch: `content/schema/poi.schema.json` explicitly allows `position: null` (coordinates not yet confirmed from official material), but `NeonCompass/Core/Map/POI.swift`'s `position` field is non-optional — so any POI published with a pending position would silently fail to decode and vanish from the app (swallowed by the existing tolerant `compactMap`/`do-catch` decode path, with no visible error to anyone).

**Architecture:** Make `POI.position` optional (`NormalizedPoint?`), matching the schema exactly. Exclude position-pending POIs from what actually renders on the map (`MapModel.filteredPOIs`) — the map has no way to place a pin without coordinates — while still decoding and holding them, so a future editorial update that adds a real position needs no further code change, no re-publish-shaped workaround, and no data loss in the interim.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing. No SwiftData, Firebase, or content-pipeline changes — this is a pure Swift-model + one-filter fix.

## Global Constraints

- Swift 6 strict concurrency (unaffected — no new async/concurrency surface).
- No behavior change to POI decode tolerance: a single malformed document must still not blank the whole collection (`FirestoreContentRepository`, unchanged by this plan).
- No schema or content-pipeline change — `content/schema/poi.schema.json` already correctly allows `position: null`; this plan brings the Swift side in line with it, not the other way around.
- This plan does not touch Firestore/publishing — the 5 POI files from this week's veille batch stay as local drafts (2 pass editorial QA, 3 need reformulation per `content/inbox/qa-report-2026-07-21.md`); publishing them is a separate, later decision.

---

### Task 1: Make `POI.position` optional

**Files:**
- Modify: `NeonCompass/Core/Map/POI.swift`
- Modify: `NeonCompassTests/Map/POITests.swift`

**Interfaces:**
- Produces: `POI.position: NormalizedPoint?` (was `NormalizedPoint`). Every other `POI` field is unchanged. `NormalizedPoint` itself is unchanged.

- [ ] **Step 1: Write the failing test for null-position decode**

In `NeonCompassTests/Map/POITests.swift`, add this test (keep the existing three tests as-is, but see Step 2 for one required fix to the existing positioned-decode test):

```swift
    @Test func decodesPOIWithNullPositionAsPending() throws {
        let json = Data("""
        [{
            "id": "poi_arts_center",
            "category": "landmark",
            "position": null,
            "title": {"en": "Arts Center", "fr": "Centre culturel des arts"},
            "note": {"en": "Sample note"},
            "status": "draft",
            "sources": ["internal:fixture"]
        }]
        """.utf8)
        let pois = try POILoader.decode(json)
        #expect(pois.count == 1)
        #expect(pois[0].position == nil)
    }
```

- [ ] **Step 2: Run tests to verify the new test fails, and note the pre-existing test that will need a one-line fix**

Run: `Scripts/test.sh`
Expected: the new test fails to compile (`position` is not yet `Optional`, so `"position": null` fails to decode and `pois[0].position == nil` doesn't type-check against a non-optional). You will also need to change line 29 of the existing `decodesPOIArrayIgnoringPipelineOnlyFields` test in the same file, from:

```swift
        #expect(abs(pois[0].position.x - 0.7312) < 0.0001)
```

to:

```swift
        #expect(abs((pois[0].position?.x ?? -1) - 0.7312) < 0.0001)
```

Make this edit now, in the same commit as Step 3-4 — it is required for the file to compile once `position` becomes optional, not an independent behavior change.

- [ ] **Step 3: Make `position` optional**

In `NeonCompass/Core/Map/POI.swift`, change:

```swift
struct POI: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: POICategory
    let position: NormalizedPoint
    let title: LocalizedText
```

to:

```swift
struct POI: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: POICategory
    let position: NormalizedPoint?
    let title: LocalizedText
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `decodesPOIWithNullPositionAsPending` test and the fixed `decodesPOIArrayIgnoringPipelineOnlyFields` test. This step will very likely also surface a compile error in `NeonCompass/Features/Map/MapPinsOverlay.swift:15` (`MapGeometry.screenPosition(for: poi.position, ...)` now receives an `Optional`) — that call site is fixed in Task 2, not this task; if `Scripts/build.sh` (not `test.sh`) fails here, that is expected and will be resolved by Task 2. `Scripts/test.sh` alone should still succeed since the test target doesn't compile `MapPinsOverlay`'s body against real data the same way — if it does NOT succeed because of this, stop and flag it (do not fix `MapPinsOverlay` in this task — that violates Task 2's scope boundary below).

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Map/POI.swift NeonCompassTests/Map/POITests.swift
git commit -m "fix: POI.position is optional, matching poi.schema.json's null-position (coordinates pending) case"
```

---

### Task 2: Exclude position-pending POIs from the map, add regression coverage

**Files:**
- Modify: `NeonCompass/Features/Map/MapModel.swift`
- Modify: `NeonCompass/Features/Map/MapPinsOverlay.swift`
- Modify: `NeonCompassTests/Map/MapModelTests.swift`

**Interfaces:**
- Consumes: `POI.position: NormalizedPoint?` (Task 1).
- Produces: `MapModel.filteredPOIs` now also excludes any POI with `position == nil` — a position-pending POI is decoded and held in `MapModel.pois`, but never appears in `filteredPOIs`, so it can never reach `MapPinsOverlay`, never renders a pin, and can never become `selectedPOI` (which is only ever set from a pin tap). No new public API — `filteredPOIs`'s existing signature and callers are unchanged, only its filtering predicate changes.

- [ ] **Step 1: Write the failing test**

In `NeonCompassTests/Map/MapModelTests.swift`, add this test (leave `samplePOIs()` and the other existing tests unchanged):

```swift
    @Test func filteredPOIsExcludesPositionPendingPOIs() {
        let pending = POI(id: "c", category: .landmark, position: nil,
                           title: LocalizedText(en: "Pending", fr: nil, es: nil, it: nil, de: nil), note: nil)
        let model = MapModel(pois: samplePOIs() + [pending], modelContext: makeContext())
        #expect(model.filteredPOIs.map(\.id) == ["a", "b"])
        #expect(model.pois.map(\.id) == ["a", "b", "c"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/test.sh`
Expected: FAIL — `filteredPOIs` currently includes the position-pending POI (category/search filters don't yet check `position`), so `model.filteredPOIs.map(\.id)` would be `["a", "b", "c"]`, not `["a", "b"]`.

- [ ] **Step 3: Exclude position-pending POIs from `filteredPOIs`**

In `NeonCompass/Features/Map/MapModel.swift`, change:

```swift
    var filteredPOIs: [POI] {
        let languageCode = currentLanguageCode
        return pois.filter { poi in
            activeCategories.contains(poi.category)
                && (searchQuery.isEmpty
                    || poi.title.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
    }
```

to:

```swift
    var filteredPOIs: [POI] {
        let languageCode = currentLanguageCode
        return pois.filter { poi in
            poi.position != nil
                && activeCategories.contains(poi.category)
                && (searchQuery.isEmpty
                    || poi.title.resolved(for: languageCode).localizedCaseInsensitiveContains(searchQuery))
        }
    }
```

- [ ] **Step 4: Fix `MapPinsOverlay`'s now-optional `position` access**

`MapPinsOverlay` only ever receives `filteredPOIs` (wired in `MapScreen.mapCanvas`), which after Step 3 can never contain a `nil` position — but the compiler doesn't know that from the type alone, since `MapPinsOverlay.pois: [POI]` accepts any `POI` array. In `NeonCompass/Features/Map/MapPinsOverlay.swift`, change:

```swift
    var body: some View {
        ForEach(pois) { poi in
            let position = MapGeometry.screenPosition(for: poi.position, manifest: manifest, viewport: viewport)
```

to:

```swift
    var body: some View {
        ForEach(pois) { poi in
            guard let poiPosition = poi.position else { return }
            let position = MapGeometry.screenPosition(for: poiPosition, manifest: manifest, viewport: viewport)
```

(A `guard ... else { return }` inside `ForEach`'s closure skips just that element, matching Swift's `ForEach`/`ViewBuilder` semantics — this is a defensive guard for a case that `filteredPOIs` already prevents in practice, not a behavior change to what actually renders.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`, including the new `filteredPOIsExcludesPositionPendingPOIs` test.

- [ ] **Step 6: Build the app**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Map/MapModel.swift NeonCompass/Features/Map/MapPinsOverlay.swift NeonCompassTests/Map/MapModelTests.swift
git commit -m "fix: exclude position-pending POIs from the map, guard MapPinsOverlay against optional position"
```

---

## Self-Review

**Couverture** : le décalage identifié (schema autorise `position: null`, modèle Swift ne l'autorisait pas) est corrigé de bout en bout — décodage (Task 1) et affichage carte (Task 2). Testé aux deux niveaux : `POITests` pour le décodage, `MapModelTests` pour l'exclusion du rendu.

**Portée** : aucune modification du schema, du pipeline de contenu, ou de Firestore — seul le modèle Swift et le filtrage carte changent. Les 5 fichiers POI de la veille du 21/07 restent des drafts locaux, non publiés ; ce plan ne préjuge pas de la décision éditoriale (reformulation nécessaire sur 3/5, cf. `qa-report-2026-07-21.md`) ni du moment de leur publication.

**Cohérence des types** : `NormalizedPoint?` introduit une seule fois (Task 1), consommé par `MapModel.filteredPOIs` et `MapPinsOverlay` (Task 2) sans nouvelle abstraction.

**Ce que ce plan ne fait pas (volontairement)** : il ne surface pas les POI en attente de position ailleurs dans l'app (pas de liste « à localiser », pas d'indicateur dans Progression) — au-delà du scope du problème signalé (silent data loss), et rien dans le spec ne demande une UI dédiée pour cet état transitoire. Si un besoin concret apparaît (ex. Progression doit compter ces POI dans un total), le retravailler à ce moment-là plutôt que d'anticiper maintenant.
