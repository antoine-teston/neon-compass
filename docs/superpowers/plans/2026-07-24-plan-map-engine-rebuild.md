# Map Engine Rebuild (delete CATiledLayer, pins in content space) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Map screen's `CATiledLayer`-based rendering engine with a direct-image approach, and move every pin overlay (POI, personal pins, community spots) into the scroll view's zooming content view so they transform on the same clock as the map — eliminating the two structural defects identified in `.superpowers/sdd/map-architecture-research.md`: CATiledLayer is the wrong tool for a single bounded ~2048px image (async pop-in, a hard `maximumZoomScale = 1` ceiling, a documented iOS 26 CATiledLayer-under-SwiftUI crash class), and pins positioned from a `@State viewport` pushed one run-loop behind the scroll view's own render-server-driven transform (the "pins swim/lag" defect).

**Architecture:** Keep `MapGeometry`'s normalized-coordinate contract and `FitToBoundsScrollView`'s fit/cover/center math completely unchanged (both already correct, per the research). Delete `TilePyramid`/`TiledCanvasView`. The scroll view's zoomed content becomes a single SwiftUI view (`MapContentSwiftUIView`: the map image plus every pin type, all positioned in content-space coordinates with no `MapViewport` dependency) hosted via one `UIHostingController`, so `UIScrollView` applies its zoom/pan transform to the pins automatically — the lag disappears by construction, not by tuning. `MapPinsOverlay`/`PersonalPinsOverlay` (separate SwiftUI siblings repositioned every scroll frame) and `MapGeometry.screenPosition` (their now-unnecessary viewport-relative positioning function) are deleted once nothing calls them.

**Tech Stack:** SwiftUI, UIKit (`UIScrollView` + `UIHostingController`, confined to the existing single `Core/Map/` engine file per CLAUDE.md), Swift Testing, Node/sharp (map art regeneration tooling).

## Global Constraints

- **UIKit confined to one file** (CLAUDE.md: "UIKit seulement si une API l'impose, wrapped in one file") — the engine file (renamed from `TiledMapView.swift` to `MapScrollView.swift`, since "Tiled" is no longer accurate) stays the only UIKit in `Core/Map/`; `MapContentSwiftUIView` is pure SwiftUI, defined in that same file for cohesion since it's what the `UIHostingController` hosts.
- **iPad-first-class (CLAUDE.md):** every visual check in this plan must cover both `sizeClass == .compact` and regular/`sidebarAdaptable` width.
- **Swift 6 strict concurrency, SwiftUI only.**
- **Tests: Swift Testing.**
- **No Rockstar/Take-Two assets (CLAUDE.md, spec §1):** the regenerated map art in this plan is rendered from the SAME existing original placeholder source (`tools/basemap/island-placeholder.svg`) — no new art is introduced, only how it's packaged (one flat image instead of a tile pyramid) changes.
- **No UI test target exists** — every visual fix must still get a real Simulator check by the implementer, reported honestly, using ONLY `xcrun simctl` (install/launch/`io <udid> screenshot`) for automation. Do NOT use `osascript`/AppleScript/"System Events"/arbitrary `screencapture` to interact with the Simulator window — a prior task in this session accidentally interacted with the real desktop that way and captured unrelated private content. If a specific interactive state (e.g. live pinch/pan, a button tap) can't be reached via `simctl` alone, say so honestly rather than attempting screen automation.

## File Structure

- Modify: `tools/basemap/tile.js` — Task 1 (emit one flat image instead of a tile pyramid).
- Create: `NeonCompass/Resources/MapArt/island.png`, `NeonCompass/Resources/MapArt/manifest.json` — Task 1 (regenerated asset, replaces `NeonCompass/Resources/MapTiles/`).
- Delete: `NeonCompass/Resources/MapTiles/` (the old 85-tile pyramid + its manifest) — Task 1.
- Modify: `project.yml` — Task 1 (resource folder reference: `MapTiles` → `MapArt`).
- Modify: `NeonCompass/Core/Map/TileManifest.swift` — Task 1 (rename type to `MapManifest`, simplify fields to just `size`).
- Modify: `NeonCompassTests/Map/TileManifestTests.swift` → rename to `MapManifestTests.swift` — Task 1.
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` — Task 1 (`fullSize(for:)` takes `MapManifest`, reads `.size`); Task 2 (new `contentPoint(for:manifest:)`, remove `screenPosition` — see Task 3, not Task 2, for the actual removal, since Task 2's new engine doesn't call it but Task 3's cleanup is what makes it safe to delete).
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift` — Task 1 (update the shared `manifest` fixture's type/fields); Task 2 (add `contentPoint` tests); Task 3 (remove the 2 now-obsolete `screenPosition` tests).
- Rename + rewrite: `NeonCompass/Core/Map/TiledMapView.swift` → `NeonCompass/Core/Map/MapScrollView.swift` — Task 2 (delete `TilePyramid`/`TiledCanvasView`, add `MapContentSwiftUIView` + `MapArtLoader`, rewrite `TiledMapRepresentable`'s interface and `Coordinator`).
- Modify: `NeonCompass/Features/Map/MapScreen.swift` — Task 2 (new `TiledMapRepresentable` call site; remove the `MapPinsOverlay`/`PersonalPinsOverlay`/community `ForEach` block from `mapCanvas`).
- Delete: `NeonCompass/Features/Map/MapPinsOverlay.swift`, `NeonCompass/Features/Map/PersonalPinsOverlay.swift` — Task 3 (now unused).

## Task 1: Flat map art asset + simplified manifest

**Files:**
- Modify: `tools/basemap/tile.js`
- Create: `NeonCompass/Resources/MapArt/island.png`, `NeonCompass/Resources/MapArt/manifest.json`
- Delete: `NeonCompass/Resources/MapTiles/`
- Modify: `project.yml`
- Modify: `NeonCompass/Core/Map/TileManifest.swift` (rename `MapManifest.swift`)
- Modify: `NeonCompassTests/Map/TileManifestTests.swift` (rename `MapManifestTests.swift`)
- Modify: `NeonCompass/Core/Map/MapGeometry.swift`, `NeonCompassTests/Map/MapGeometryTests.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift` (one line — the `manifest` fallback literal)

**Interfaces:**
- Produces: `MapManifest` (renamed from `TileManifest`) — `struct MapManifest: Codable, Equatable, Sendable { let size: Int }`, `static func load(from bundle: Bundle = .main) -> MapManifest?` (now looks in a `MapArt` subdirectory). `MapGeometry.fullSize(for: MapManifest) -> CGFloat` — same formula intent, now just `CGFloat(manifest.size)`.
- Consumes: nothing from other tasks — this task is self-contained and independently buildable/testable (it only changes the manifest's shape and the art's packaging, not the engine itself, which still works with `TiledCanvasView`/`TilePyramid` until Task 2).

**Context:** The current pipeline (`tools/basemap/tile.js`) renders the source SVG at each zoom level and slices it into 256px tiles (85 files, 500 KB total) for `CATiledLayer` streaming. Since Task 2 deletes `CATiledLayer` entirely in favor of a single `UIImageView`-style direct image, the tiled packaging is no longer needed — a single flat PNG at the native resolution (2048×2048, matching the current `maxZoom=3` pyramid's top level) is both simpler and sufficient (the whole image is 500 KB, easily fits in memory). `tile.js` is rewritten to emit exactly that, using the identical `sharp` rasterization call the old pipeline already used for its top zoom level (`density: 72 * grid` at `size = TILE * grid`), so the art is pixel-identical to what's already bundled and reviewed — this is a packaging change, not a re-render with different output.

- [ ] **Step 1: Rewrite `tools/basemap/tile.js` to emit one flat image**

```js
#!/usr/bin/env node
// Générateur d'image de carte — brique A3 du pipeline (docs/superpowers/
// plans/2026-07-20-data-pipeline-pseudocode.md). Rend un SVG carré en une
// image plate unique — la pyramide de tuiles CATiledLayer a été retirée
// (docs/superpowers/plans/2026-07-24-plan-map-engine-rebuild.md) : la carte
// est une image unique bornée (~500 Ko), pas un document gigapixel, donc pas
// besoin de streaming par tuiles.
//   node tile.js [input.svg] [outDir] [size]
// Défauts : island-placeholder.svg → ./out, size 2048.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

const HERE = dirname(fileURLToPath(import.meta.url));

const input = process.argv[2] ?? join(HERE, 'island-placeholder.svg');
const outDir = process.argv[3] ?? join(HERE, 'out');
const size = Number(process.argv[4] ?? 2048);

mkdirSync(outDir, { recursive: true });
// sharp re-rasterise le SVG à la densité voulue, donc les traits restent
// nets à la résolution cible — même technique que l'ancienne pyramide de
// tuiles pour son niveau de zoom le plus détaillé.
const density = 72 * (size / 256);
const image = await sharp(input, { density }).resize(size, size).png().toBuffer();
await sharp(image).toFile(join(outDir, 'island.png'));

const manifest = {
  size,
  source: input.split('/').pop(),
  sourceSha256: createHash('sha256').update(await sharp(input).toBuffer()).digest('hex').slice(0, 16),
};
writeFileSync(join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`island.png (${size}×${size}) + manifest.json → ${outDir}`);
```

- [ ] **Step 2: Regenerate the asset and place it in the app bundle location**

```bash
cd tools/basemap
node tile.js island-placeholder.svg out 2048
mkdir -p ../../NeonCompass/Resources/MapArt
cp out/island.png out/manifest.json ../../NeonCompass/Resources/MapArt/
rm -rf out
```
Then remove the old tiled asset directory entirely:
```bash
git rm -r NeonCompass/Resources/MapTiles
```

- [ ] **Step 3: Update `project.yml`'s resource folder reference**

Find the two entries referencing `Resources/MapTiles` (an exclude on the main `NeonCompass` source path, and a `type: folder` resource entry — see the existing `project.yml:47-52` pattern) and change both `MapTiles` occurrences to `MapArt`.

- [ ] **Step 4: Rename and simplify `TileManifest.swift` → `MapManifest.swift`**

```bash
git mv NeonCompass/Core/Map/TileManifest.swift NeonCompass/Core/Map/MapManifest.swift
```

Replace its contents:

```swift
import Foundation

/// Décrit l'image de carte générée par tools/basemap/tile.js. Un seul champ
/// depuis le retrait de CATiledLayer (docs/superpowers/plans/2026-07-24-
/// plan-map-engine-rebuild.md) — plus de pyramide de tuiles à décrire.
struct MapManifest: Codable, Equatable, Sendable {
    let size: Int

    static func load(from bundle: Bundle = .main) -> MapManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MapArt"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapManifest.self, from: data)
    }
}
```

- [ ] **Step 5: Rename and rewrite the manifest's test**

```bash
git mv NeonCompassTests/Map/TileManifestTests.swift NeonCompassTests/Map/MapManifestTests.swift
```

```swift
import Testing
import Foundation
@testable import NeonCompass

struct MapManifestTests {
    @Test func decodesManifest() throws {
        let json = Data("""
        {"size": 2048, "source": "island-placeholder.svg", "sourceSha256": "abc123"}
        """.utf8)
        let manifest = try JSONDecoder().decode(MapManifest.self, from: json)
        #expect(manifest.size == 2048)
    }
}
```

- [ ] **Step 6: Update `MapGeometry.fullSize(for:)` to the new manifest shape**

In `NeonCompass/Core/Map/MapGeometry.swift`, change:

```swift
    static func fullSize(for manifest: TileManifest) -> CGFloat {
        CGFloat(manifest.tileSize * (1 << manifest.maxZoom))
    }
```
to:

```swift
    static func fullSize(for manifest: MapManifest) -> CGFloat {
        CGFloat(manifest.size)
    }
```
Every other function signature in `MapGeometry.swift` that takes `manifest: TileManifest` (`screenPosition`, `normalizedPoint`, and the fit/cover/centering functions added in earlier plans) changes its parameter type to `MapManifest` — a pure rename, no logic changes.

- [ ] **Step 7: Update `MapGeometryTests.swift`'s shared fixture**

Change the one declaration:
```swift
    let manifest = TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)
```
to:
```swift
    let manifest = MapManifest(size: 2048)
```
And update the one test that names the old fields:
```swift
    @Test func fullSizeIsTileSizeTimesTwoPowMaxZoom() {
        #expect(MapGeometry.fullSize(for: manifest) == CGFloat(256 * 8))
    }
```
to:
```swift
    @Test func fullSizeMatchesTheManifestSize() {
        #expect(MapGeometry.fullSize(for: manifest) == 2048)
    }
```
Every other test in this file that references `TileManifest(...)` as a literal (rather than the shared `manifest` property) should use `MapManifest(size: 2048)` instead — check for any such inline constructions in the `fitZoomScale`/`coverZoomScale`/`centeringInsets`/`centeredContentOffset` tests added in earlier plans; those tests construct `CGSize` values directly and don't reference the manifest type, so no further changes are expected there, but verify.

- [ ] **Step 8: Update `MapScreen.swift`'s manifest fallback**

Change:
```swift
    private let manifest = TileManifest.load() ?? TileManifest(tileSize: 256, maxZoom: 3, tileCount: 85)
```
to:
```swift
    private let manifest = MapManifest.load() ?? MapManifest(size: 2048)
```
(This is the only line in `MapScreen.swift` this task touches — the engine rewrite and pin integration are Task 2.)

- [ ] **Step 9: Regenerate the Xcode project and build**

Run: `xcodegen generate` (picks up the `project.yml` resource-folder rename), then `Scripts/build.sh`.
Expected: `** BUILD SUCCEEDED **`. This will fail to compile until every `TileManifest` reference above is updated to `MapManifest` — that's expected mid-task, not a regression signal.

- [ ] **Step 10: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (test count unchanged from before this task — pure rename/simplification, no new or removed test cases beyond the one renamed `fullSize...` test).

- [ ] **Step 11: Commit**

```bash
git add tools/basemap/tile.js NeonCompass/Resources/MapArt NeonCompass/Resources/MapTiles project.yml \
  NeonCompass/Core/Map/MapManifest.swift NeonCompass/Core/Map/MapGeometry.swift \
  NeonCompassTests/Map/MapManifestTests.swift NeonCompassTests/Map/MapGeometryTests.swift \
  NeonCompass/Features/Map/MapScreen.swift NeonCompass.xcodeproj
git commit -m "refactor: replace the CATiledLayer tile pyramid with a single flat map image (MapManifest, was TileManifest)"
```

## Task 2: Core engine rewrite — delete CATiledLayer, host pins in the zooming content view

**Files:**
- Rename + rewrite: `NeonCompass/Core/Map/TiledMapView.swift` → `NeonCompass/Core/Map/MapScrollView.swift`
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` (add `contentPoint(for:manifest:)`)
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift` (add `contentPoint` tests)
- Modify: `NeonCompass/Features/Map/MapScreen.swift`

**Interfaces:**
- Consumes: `MapManifest`, `MapGeometry.fullSize`/`normalizedPoint` (Task 1, unchanged beyond the rename), `MapModel.filteredPOIs`/`.personalPins`/`.isFound(_:)`/`.selectedPOI`, `CommunityModel.visibleSpots`/`.vote(on:direction:)`/`.report(_:reason:)`/`.block(authorUid:)`, `Contribution` (`Core/Community/Contribution.swift`), `VoteDirection` (`Core/Community/ContributionFunctionsCalling.swift`), `ContributionAnnotationView` (`Features/Community/ContributionAnnotationView.swift`) — all pre-existing, unchanged by this task.
- Produces: `TiledMapRepresentable`'s new initializer shape — `TiledMapRepresentable(manifest:pois:personalPins:communitySpots:isFound:viewport:onLongPress:onTapPOI:onVote:onReport:onBlockAuthor:)`. `MapGeometry.contentPoint(for:manifest:) -> CGPoint` (pure, viewport-independent — this is ALL pin positioning needs going forward).

**Context — why this is one task, not two:** changing `TiledMapRepresentable`'s public interface (adding the new `pois`/`personalPins`/`communitySpots`/`isFound`/`onTapPOI`/`onVote`/`onReport`/`onBlockAuthor` parameters) and updating its only call site (`MapScreen.mapCanvas`) must land together — the build breaks between them otherwise. This is the core structural fix: today, `MapPinsOverlay`/`PersonalPinsOverlay`/the community `ForEach` in `MapScreen.mapCanvas` are separate SwiftUI siblings, repositioned every frame from a `@State viewport` pushed out of `scrollViewDidScroll`/`DidZoom` — the scroll view moves its content on the render server, and the pins only catch up one run-loop later on the main thread, which is the "pins swim/lag" defect. Moving every pin type into `MapContentSwiftUIView` — the single SwiftUI view hosted (via `UIHostingController`) as the scroll view's zooming content itself — means `UIScrollView` applies its zoom/pan transform to the pins automatically, since they're now genuinely inside the transformed view rather than a sibling being kept in sync by state. The lag is eliminated by construction, not mitigated. As a direct freebie, pin positioning math also gets simpler: `MapGeometry.contentPoint(for:manifest:)` needs no `MapViewport` at all (no `zoomScale`/`contentOffset`) — content-space position is just `normalized × fullSize`, unconditionally.

This task also removes the CATiledLayer-specific `maximumZoomScale = 1` ceiling (a direct image can be zoomed in past native resolution with acceptable interpolation, unlike a tile pyramid that tops out at its top LOD) and adds the "found" state visibly to POI pins on the map itself (today it's only shown in the detail sheet — the single highest-value UX borrow identified from the mapgenie.io research, and nearly free now that pins are real SwiftUI content again).

`MapGeometry.screenPosition` (the old viewport-relative positioning function `MapPinsOverlay`/`PersonalPinsOverlay`/the community `ForEach` used) is intentionally **not removed in this task** — it becomes unused here but is still referenced by the two overlay files this task doesn't touch yet. Removing it now would leave those files with a dangling reference. Task 3 deletes both the dead overlay files and `screenPosition` together, once nothing calls either.

- [ ] **Step 1: Add `MapGeometry.contentPoint` and its tests**

Add to `NeonCompass/Core/Map/MapGeometry.swift` (inside `enum MapGeometry`, alongside the other functions):

```swift
    /// A point's position in content-space (full-resolution, un-zoomed) —
    /// ALL pin positioning needs now that pins live inside the same view the
    /// scroll view zooms/pans (see Plan: map-engine-rebuild). Deliberately
    /// takes no `MapViewport` — no `zoomScale`/`contentOffset` — because the
    /// content view's own transform IS the zoom/pan, applied uniformly to
    /// everything inside it, pins included.
    static func contentPoint(for point: NormalizedPoint, manifest: MapManifest) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(x: CGFloat(point.x) * full, y: CGFloat(point.y) * full)
    }
```

Add to `NeonCompassTests/Map/MapGeometryTests.swift` (append inside `struct MapGeometryTests`):

```swift
    @Test func contentPointAtOriginIsOrigin() {
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 0, y: 0), manifest: manifest)
        #expect(point == .zero)
    }

    @Test func contentPointScalesByFullSizeOnly() {
        // manifest.size == 2048 (Task 1's fixture) — no zoom/offset involved.
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 0.5, y: 0.25), manifest: manifest)
        #expect(point == CGPoint(x: 1024, y: 512))
    }

    @Test func contentPointAtBottomRightIsFullSize() {
        let point = MapGeometry.contentPoint(for: NormalizedPoint(x: 1, y: 1), manifest: manifest)
        #expect(point == CGPoint(x: 2048, y: 2048))
    }
```

Run: `Scripts/test.sh -only-testing:NeonCompassTests/MapGeometryTests`
Expected: all pass, including the 3 new tests.

- [ ] **Step 2: Rename and rewrite the engine file**

```bash
git mv NeonCompass/Core/Map/TiledMapView.swift NeonCompass/Core/Map/MapScrollView.swift
```

Replace its entire contents:

```swift
import SwiftUI
import UIKit

/// Moteur de la carte — seule pièce UIKit (UIScrollView : pas d'équivalent
/// SwiftUI pour zoom/pan momentum natif). Le contenu zoomé lui-même (image +
/// tous les pins) est une unique vue SwiftUI hébergée via UIHostingController
/// — parce qu'UIScrollView applique son transform de zoom/pan directement à
/// cette vue hébergée, les pins bougent AVEC la carte, sur la même horloge :
/// plus de décalage d'une frame comme avec l'ancien design (pins en overlay
/// SwiftUI séparé, repositionnés via un @State poussé depuis
/// scrollViewDidScroll — la carte bouge côté render server, les pins
/// rattrapaient une frame plus tard côté main thread). CLAUDE.md : "UIKit
/// seulement si une API l'impose, wrapped in one file" — tout le moteur
/// (scroll view + contenu hébergé) reste dans ce seul fichier.

/// Charge l'image de carte plate une seule fois — l'image entière (~500 Ko)
/// tient largement en mémoire, donc pas besoin de streaming par tuiles.
private enum MapArtLoader {
    static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "island", withExtension: "png", subdirectory: "MapArt") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()
}

/// Contenu SwiftUI hébergé — l'image de la carte plus tous les pins, en
/// coordonnées de contenu plein-résolution (indépendantes du zoom/pan
/// courant, voir `MapGeometry.contentPoint`). `zoomScale` n'est utilisé QUE
/// pour garder les pins à une taille visuelle constante à l'écran
/// (contre-échelle 1/zoomScale) — jamais pour repositionner quoi que ce soit.
private struct MapContentSwiftUIView: View {
    let manifest: MapManifest
    let pois: [POI]
    let personalPins: [PersonalPin]
    let communitySpots: [Contribution]
    let isFound: (POI) -> Bool
    var zoomScale: CGFloat = 1
    let onTapPOI: (POI) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void

    private var fullSize: CGFloat { MapGeometry.fullSize(for: manifest) }
    private var pinScale: CGFloat { 1 / max(zoomScale, 0.01) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let mapImage = MapArtLoader.image {
                Image(uiImage: mapImage)
                    .resizable()
                    .frame(width: fullSize, height: fullSize)
            }
            ForEach(pois) { poi in
                if let position = poi.position {
                    poiPin(poi, at: position)
                }
            }
            ForEach(personalPins) { pin in
                personalPin(pin)
            }
            ForEach(communitySpots) { spot in
                ContributionAnnotationView(
                    spot: spot,
                    onVote: { direction in onVote(spot, direction) },
                    onReport: { onReport(spot) },
                    onBlockAuthor: { onBlockAuthor(spot) }
                )
                .position(MapGeometry.contentPoint(for: spot.position, manifest: manifest))
                .scaleEffect(pinScale)
            }
        }
        .frame(width: fullSize, height: fullSize)
    }

    private func poiPin(_ poi: POI, at position: NormalizedPoint) -> some View {
        let found = isFound(poi)
        return Button {
            onTapPOI(poi)
        } label: {
            Image(systemName: found ? "checkmark.circle.fill" : "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(found ? NCColor.neonCyan.opacity(0.4) : NCColor.neonCyan)
                .shadow(color: NCColor.neonCyan.opacity(found ? 0.2 : 0.6), radius: 4)
        }
        .position(MapGeometry.contentPoint(for: position, manifest: manifest))
        .scaleEffect(pinScale)
        .accessibilityLabel(Text(poi.title.resolved(for: Self.currentLanguageCode)))
    }

    private func personalPin(_ pin: PersonalPin) -> some View {
        Image(systemName: "star.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(NCColor.sunsetOrange)
            .position(MapGeometry.contentPoint(for: NormalizedPoint(x: pin.x, y: pin.y), manifest: manifest))
            .scaleEffect(pinScale)
            .accessibilityLabel(Text(pin.title))
    }

    private static var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}

/// Calcule et applique un zoom/centrage adapté au viewport réel une fois les
/// bounds connus — voir les plans UX-polish (rounds 1 et 2) pour l'historique
/// complet de cette logique fit/cover/center ; INCHANGÉE par ce plan.
private final class FitToBoundsScrollView: UIScrollView {
    var contentNativeSize: CGSize = .zero
    private var lastFittedBoundsSize: CGSize = .zero
    private var hasPerformedInitialFit = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastFittedBoundsSize,
              bounds.width > 0, bounds.height > 0,
              contentNativeSize != .zero else { return }
        lastFittedBoundsSize = bounds.size

        let containScale = MapGeometry.fitZoomScale(contentSize: contentNativeSize, in: bounds.size)
        minimumZoomScale = containScale

        if !hasPerformedInitialFit {
            hasPerformedInitialFit = true
            let coverScale = MapGeometry.coverZoomScale(contentSize: contentNativeSize, in: bounds.size)
            zoomScale = coverScale
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            contentOffset = MapGeometry.centeredContentOffset(contentSize: contentNativeSize, zoomScale: coverScale, in: bounds.size)
        } else {
            zoomScale = max(zoomScale, minimumZoomScale)
            let insets = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
            contentInset = UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
        }
    }
}

struct TiledMapRepresentable: UIViewRepresentable {
    let manifest: MapManifest
    let pois: [POI]
    let personalPins: [PersonalPin]
    let communitySpots: [Contribution]
    let isFound: (POI) -> Bool
    @Binding var viewport: MapViewport
    let onLongPress: (CGPoint) -> Void
    let onTapPOI: (POI) -> Void
    let onVote: (Contribution, VoteDirection) -> Void
    let onReport: (Contribution) -> Void
    let onBlockAuthor: (Contribution) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitToBoundsScrollView()
        // Le moteur gère lui-même son centrage entier via contentInset
        // calculé (voir FitToBoundsScrollView.layoutSubviews) — laisser le
        // système empiler en plus les safe-area insets (comportement
        // .automatic par défaut) rendrait la position de repos asymétrique.
        scrollView.contentInsetAdjustmentBehavior = .never
        let fullSize = MapGeometry.fullSize(for: manifest)

        let hostingController = UIHostingController(rootView: makeContent(zoomScale: 1))
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: fullSize, height: fullSize)

        scrollView.contentSize = hostingController.view.frame.size
        scrollView.contentNativeSize = hostingController.view.frame.size
        scrollView.addSubview(hostingController.view)
        // Plus de plafond à 1 imposé par une pyramide CATiledLayer — une
        // image directe peut être zoomée au-delà de sa résolution native
        // avec une interpolation acceptable, ce qui rend la carte réellement
        // explorable plutôt que statique une fois entièrement affichée.
        scrollView.maximumZoomScale = 2.5
        scrollView.delegate = context.coordinator
        context.coordinator.contentView = hostingController.view
        context.coordinator.hostingController = hostingController
        scrollView.backgroundColor = .black

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.sync(scrollView)
        }

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        scrollView.addGestureRecognizer(longPress)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Rafraîchit les données (pois/personalPins/communitySpots) sans
        // écraser le zoomScale que `Coordinator.sync` maintient déjà en
        // direct sur chaque frame de scroll/zoom — on relit le zoomScale
        // courant du rootView plutôt que d'en repartir de 1.
        let currentZoom = context.coordinator.hostingController?.rootView.zoomScale ?? viewport.zoomScale
        context.coordinator.hostingController?.rootView = makeContent(zoomScale: currentZoom)
    }

    private func makeContent(zoomScale: CGFloat) -> MapContentSwiftUIView {
        MapContentSwiftUIView(
            manifest: manifest,
            pois: pois,
            personalPins: personalPins,
            communitySpots: communitySpots,
            isFound: isFound,
            zoomScale: zoomScale,
            onTapPOI: onTapPOI,
            onVote: onVote,
            onReport: onReport,
            onBlockAuthor: onBlockAuthor
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var contentView: UIView?
        var hostingController: UIHostingController<MapContentSwiftUIView>?
        @Binding private var viewport: MapViewport
        private let onLongPress: (CGPoint) -> Void

        init(viewport: Binding<MapViewport>, onLongPress: @escaping (CGPoint) -> Void) {
            _viewport = viewport
            self.onLongPress = onLongPress
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { sync(scrollView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { sync(scrollView) }

        fileprivate func sync(_ scrollView: UIScrollView) {
            let newViewport = MapViewport(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
            viewport = newViewport
            // Poussé directement ici (pas via updateUIView) : ce chemin
            // s'exécute sur CHAQUE frame de scroll/zoom, donc c'est le point
            // le moins coûteux pour garder les pins à taille constante à
            // l'écran (contre-échelle) sans dépendre d'un aller-retour par
            // SwiftUI côté MapScreen.
            hostingController?.rootView.zoomScale = newViewport.zoomScale
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let contentView else { return }
            onLongPress(gesture.location(in: contentView))
        }
    }
}
```

- [ ] **Step 3: Update `MapScreen.swift`'s `mapCanvas` to the new interface, removing the old overlay usage**

Replace `mapCanvas(model:)`'s opening `ZStack` (the part building `TiledMapRepresentable`, `MapPinsOverlay`, `PersonalPinsOverlay`, and the community `ForEach`) with:

```swift
    private func mapCanvas(model: MapModel) -> some View {
        ZStack(alignment: .topLeading) {
            TiledMapRepresentable(
                manifest: manifest,
                pois: model.filteredPOIs,
                personalPins: model.personalPins,
                communitySpots: communityModel?.visibleSpots ?? [],
                isFound: model.isFound,
                viewport: $viewport,
                onLongPress: { canvasPoint in
                    pendingPinLocation = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
                    showLongPressMenu = true
                },
                onTapPOI: { poi in model.selectedPOI = poi },
                onVote: { spot, direction in
                    Task { await communityModel?.vote(on: spot, direction: direction) }
                },
                onReport: { spot in
                    Task { await communityModel?.report(spot, reason: nil) }
                },
                onBlockAuthor: { spot in
                    if let authorUid = spot.authorUid { communityModel?.block(authorUid: authorUid) }
                }
            )

            VStack(spacing: 12) {
                Button {
                    showPersonalPinList = true
                } label: {
                    Image(systemName: "star.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                if proEntitlementModel.isProEntitled {
                    Button {
                        showRoutePlanner = true
                    } label: {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(16)
        }
        .onAppear {
            communityModel?.refreshBlockedAuthors()
            reattachSyncIfNeeded()
        }
        .sheet(isPresented: $showPersonalPinList) {
            PersonalPinListSheet(model: model)
        }
        .sheet(isPresented: $showRoutePlanner) {
            RoutePlannerSheet(
                route: RoutePlanner.greedyRoute(
                    from: model.pois.filter { $0.category == .collectible && $0.position != nil && !model.isFound($0) }
                ),
                languageCode: Self.currentLanguageCode()
            )
        }
        .alert(
            "map.personalPins.addPrompt",
            isPresented: $showPersonalPinAlert
        ) {
            TextField("map.personalPins.addPrompt", text: $pendingPinTitle)
            Button("map.personalPins.save") {
                if let location = pendingPinLocation, !pendingPinTitle.isEmpty {
                    model.addPersonalPin(at: location, title: pendingPinTitle)
                }
                pendingPinTitle = ""
                pendingPinLocation = nil
                showPersonalPinAlert = false
            }
            Button("map.personalPins.cancel", role: .cancel) {
                pendingPinLocation = nil
                pendingPinTitle = ""
                showPersonalPinAlert = false
            }
        }
        .confirmationDialog("map.longPress.menuTitle", isPresented: $showLongPressMenu, titleVisibility: .visible) {
            Button("map.longPress.addPersonalPin") {
                showPersonalPinAlert = true
            }
            if communityModel?.contributionsEnabled != false {
                Button("map.longPress.proposeSpot") {
                    if authModel.userID != nil {
                        pendingContributionLocation = pendingPinLocation
                    }
                    pendingPinLocation = nil
                }
            }
            Button("map.longPress.cancel", role: .cancel) {
                pendingPinLocation = nil
            }
        }
        .sheet(item: Binding(
            get: { pendingContributionLocation.map { ContributionLocationBox(location: $0) } },
            set: { pendingContributionLocation = $0?.location }
        )) { box in
            if let communityModel {
                ContributionSubmissionSheet(
                    position: box.location,
                    onSubmit: { category, title in
                        try? await communityModel.submit(category: category, title: title, position: box.location, languageCode: Self.currentLanguageCode())
                        pendingContributionLocation = nil
                    },
                    onDismiss: { pendingContributionLocation = nil }
                )
                .presentationDetents([.medium])
            }
        }
    }
```
(This is the same function, with the `MapPinsOverlay`/`PersonalPinsOverlay`/community-`ForEach` block removed and `TiledMapRepresentable`'s call site updated to the new interface — every `.sheet`/`.alert`/`.confirmationDialog` modifier and the favorites/route-planner button `VStack` are unchanged from before.)

- [ ] **Step 4: Regenerate the Xcode project and build both schemes**

Run: `xcodegen generate` (picks up the file rename `TiledMapView.swift` → `MapScrollView.swift`), then `Scripts/build.sh`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Build and visually verify on Simulator**

Launch in Simulator, open the Map tab, and confirm:
- The map image renders correctly (this is the SAME art as before, just packaged flat instead of tiled — should look pixel-identical).
- The map still fills the screen from the first frame (cover-fit, unchanged from the prior round) and is still correctly centered.
- POI pins and personal pins render at their correct positions.
- Pan and pinch-zoom feel smooth with NO visible lag between the map and the pins moving together (this is the core fix — describe what you observe as precisely as you can).
- Pinch-zoom now goes past native resolution (up to 2.5×) rather than stopping at 1× — confirm zooming in further than before is now possible.
- Long-press still opens the add-pin/propose-spot menu at the correct location.
- Tapping a POI pin still opens its detail sheet.

Test on both compact and regular width destinations per the iPad-first-class constraint. This is the highest-risk visual change in the plan — report exactly what you can and can't confirm, honestly.

- [ ] **Step 6: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass, including the 3 new `contentPoint` tests from Step 1.

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Core/Map/MapScrollView.swift NeonCompass/Core/Map/MapGeometry.swift \
  NeonCompassTests/Map/MapGeometryTests.swift NeonCompass/Features/Map/MapScreen.swift \
  NeonCompass.xcodeproj
git commit -m "refactor: delete CATiledLayer, host every pin type inside the scroll view's zooming content so they move with the map instead of lagging a frame behind"
```

## Task 3: Remove now-dead overlay files and `MapGeometry.screenPosition`

**Files:**
- Delete: `NeonCompass/Features/Map/MapPinsOverlay.swift`, `NeonCompass/Features/Map/PersonalPinsOverlay.swift`
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` (remove `screenPosition`)
- Modify: `NeonCompassTests/Map/MapGeometryTests.swift` (remove the 2 `screenPosition` tests)

**Interfaces:**
- Consumes: nothing — this task only removes code, and only code that Task 2 already made unreachable.

**Context:** `MapPinsOverlay.swift` and `PersonalPinsOverlay.swift` positioned pins as separate SwiftUI siblings via `MapGeometry.screenPosition(for:manifest:viewport:)` — the exact "pins repositioned from a lagging `@State viewport`" pattern this whole plan exists to remove. Task 2 already stopped calling either file (their pin-rendering logic was folded into `MapContentSwiftUIView`) and stopped calling `screenPosition`. Verify this before deleting.

- [ ] **Step 1: Confirm nothing still references the files or function being deleted**

Run: `grep -rn "MapPinsOverlay\|PersonalPinsOverlay" NeonCompass/ NeonCompassTests/` — expect matches ONLY inside the two files themselves (their own type declarations), nothing else.
Run: `grep -rn "screenPosition" NeonCompass/ NeonCompassTests/` — expect matches only inside `MapGeometry.swift`'s own declaration and the 2 tests in `MapGeometryTests.swift` that are about to be removed.

If either grep turns up an unexpected caller, STOP and report — do not delete something still in use.

- [ ] **Step 2: Delete the two overlay files**

```bash
git rm NeonCompass/Features/Map/MapPinsOverlay.swift NeonCompass/Features/Map/PersonalPinsOverlay.swift
```

- [ ] **Step 3: Remove `MapGeometry.screenPosition`**

In `NeonCompass/Core/Map/MapGeometry.swift`, delete this function entirely:
```swift
    static func screenPosition(for point: NormalizedPoint, manifest: MapManifest, viewport: MapViewport) -> CGPoint {
        let full = fullSize(for: manifest)
        return CGPoint(
            x: CGFloat(point.x) * full * viewport.zoomScale - viewport.contentOffset.x,
            y: CGFloat(point.y) * full * viewport.zoomScale - viewport.contentOffset.y
        )
    }
```
Every other function in `MapGeometry.swift` (`fullSize`, `normalizedPoint`, `fitZoomScale`, `coverZoomScale`, `centeringInsets`, `centeredContentOffset`, `contentPoint`) is unchanged — this task removes exactly one function.

- [ ] **Step 4: Remove the 2 now-obsolete tests in `MapGeometryTests.swift`**

Delete these two test methods:
```swift
    @Test func screenPositionAtOriginNoZoomNoOffset() {
        let viewport = MapViewport(zoomScale: 1, contentOffset: .zero)
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0, y: 0), manifest: manifest, viewport: viewport)
        #expect(p == .zero)
    }

    @Test func screenPositionScalesWithZoomAndOffset() {
        let viewport = MapViewport(zoomScale: 0.5, contentOffset: CGPoint(x: 10, y: 20))
        let p = MapGeometry.screenPosition(for: NormalizedPoint(x: 0.5, y: 0.5), manifest: manifest, viewport: viewport)
        #expect(p == CGPoint(x: 1024 * 0.5 - 10, y: 1024 * 0.5 - 20))
    }
```
Every other test in the file is unchanged.

- [ ] **Step 5: Regenerate the Xcode project and build**

Run: `xcodegen generate` (drops the two deleted files from the project), then `Scripts/build.sh`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the full test suite**

Run: `Scripts/test.sh`
Expected: all pass (2 fewer tests than the end of Task 2 — the removed `screenPosition` tests — with no other count change).

- [ ] **Step 7: Commit**

```bash
git add -u NeonCompass/Features/Map/ NeonCompass/Core/Map/MapGeometry.swift NeonCompassTests/Map/MapGeometryTests.swift NeonCompass.xcodeproj
git commit -m "chore: remove MapPinsOverlay/PersonalPinsOverlay and MapGeometry.screenPosition, dead since the pin-in-content-space rebuild"
```

## Self-Review

**Spec coverage:** both structural defects identified in the research (`CATiledLayer` wrong-tool-for-a-bounded-image, pins in the wrong coordinate space causing lag) are fixed — Task 2 deletes `TiledCanvasView`/`TilePyramid` and moves every pin type into the scroll view's zooming content. `MapGeometry`'s normalized-coordinate contract and `FitToBoundsScrollView`'s fit/cover/center math (from the two prior UX-polish rounds) are preserved verbatim, per the research's explicit recommendation to keep what's already correct.

**Placeholder scan:** every task has complete, real code; the exact current file contents were read directly before writing this plan (not guessed) for every file being modified or replaced.

**Type consistency:** `MapManifest` (Task 1) is consumed identically by `MapGeometry`, `MapScrollView.swift`, and `MapScreen.swift`. `TiledMapRepresentable`'s new interface (Task 2) is defined and consumed together in the same task, since a signature change and its only call site cannot land as separate buildable steps.

**Deliberately out of scope (from the research, explicitly deferred, not silently dropped):** zoom-tiered "declutter by zoom" marker visibility (gta-5-map.com borrow), draggable provisional-pin placement before commit (a mapgenie.io refinement to long-press pin placement), and any clustering — all are additive UX polish on top of this structural fix, not required to resolve either defect this plan targets. The found-state-on-pin borrow (mapgenie.io's single highest-value UX lesson) IS included in Task 2 since it was nearly free once pins are real SwiftUI content again reading `MapModel.isFound(_:)`.

**Known limitation, disclosed rather than engineered around:** `updateUIView` still reconstructs the entire `MapContentSwiftUIView` (re-diffing all pins) whenever `MapScreen`'s ancestor re-renders for any reason, not just when POI/personal-pin/community-spot data genuinely changed — the live zoom-driven counter-scale update is pushed directly from `Coordinator.sync()` to avoid doing this on every scroll/zoom frame specifically, but a coarser SwiftUI-driven data refresh remains. This is an accepted, documented perf simplification consistent with the research's framing ("hundreds of pins" doesn't require immediate-mode `Canvas` drawing yet) — revisit if pin density or scroll-jank ever makes it a real problem.
