# Plan 6b-3 — Widgets & notifications suivies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the two remaining Pro features that need genuinely new platform infrastructure — home/lock screen widgets (progress ring + pinned favorite cheat) and FCM-based followed-category notifications. Third and final sub-plan of "StoreKit 2 Pro" (roadmap Plan 6b, split Core / Simple Features / Widgets+Notifications per product decision 2026-07-23). Closes out Plan 6b entirely.

**Architecture:** Widgets need a new Xcode target (a WidgetKit extension) and an App Group so the widget process — which never has access to the main app's SwiftData store or `ProEntitlementModel` — can read a small, pre-computed summary the main app writes whenever it changes. Notifications need an `AppDelegate` adaptor (FCM/APNs registration requires UIKit lifecycle hooks SwiftUI's `App` protocol doesn't expose on its own) and a new Cloud Function trigger publishing to FCM topics when a contribution is approved.

**Tech Stack:** WidgetKit, App Groups (shared `UserDefaults`), `UIApplicationDelegateAdaptor`, Firebase Cloud Messaging (already-linked `FirebaseFunctions`/`FirebaseFirestore` packages cover the Firestore-triggered publish side; FCM client SDK needs its own product, `FirebaseMessaging`), a new Firestore-triggered Cloud Function.

## Global Constraints

- **Widgets never read SwiftData or Firestore directly.** A WidgetKit extension runs in its own process with no access to the main app's `ModelContainer`/`ProEntitlementModel`. The ONLY data a widget ever sees is a small, pre-serialized summary the main app writes to a shared `UserDefaults(suiteName:)` (App Group) whenever the relevant state changes — never a live query.
- **Widget content itself is gated on Pro, but the widget can still be ADDED by anyone** — spec doesn't say to hide the widget gallery entry behind a purchase (Apple doesn't support conditionally-hiding widget types anyway); a non-Pro user who adds the widget sees an "Unlock Pro" placeholder inside it, not a broken/empty widget and not the real content.
- **Widgets are read-only, ever.** No interactive widget buttons, no `AppIntent`-driven "Trouvé ✓" from this plan — that's explicitly v1.1+ scope (Live Activity, per spec) sharing similar `SwiftData`-write-from-widget-extension plumbing this plan deliberately does not build yet. This plan's widgets show a progress ring and a pinned favorite cheat, nothing more.
- **"Notifications suivies" is category-only in this plan, not category+zone.** Spec says "catégorie/zone suivie" — zone-following would need a geographic-boundary selection UI (drawing/picking a region on the map) that doesn't exist anywhere in this app yet and is a substantial UI feature of its own. This plan ships category-following (reusing the existing `POICategory` enum, already user-facing via the map's filter chips) and explicitly defers zone-following — see Self-Review.
- **General/editorial notifications remain free, unaffected by this plan** — spec: "les notifications générales restent gratuites." This plan only adds Pro-gated FOLLOWED-category push; it does not touch or gate any existing (currently nonexistent) general notification mechanism.
- **Firebase/FCM stays behind protocols in `Core/`** — mirrors every other `Core/*` layer.
- **Push permission is opt-in and requested only when the user actually tries to follow a category** (not at app launch, not bundled into the existing ATT/UMP onboarding sequence from Plan 6a — those are ad-consent flows, a different concern; stacking an unrelated system permission prompt into that sequence would violate Apple's own "request permission at the point of relevance" guidance and this project's existing onboarding design).
- **Swift 6 strict concurrency**, verified against actual API behavior (`UNUserNotificationCenter`, `Messaging.messaging()`) rather than assumed, per this project's established discipline.
- **This plan does not implement Live Activities or Apple Watch** — both explicitly v1.1+ per spec, out of scope for v1.0 entirely, not just this plan.

---

## File Structure

```
NeonCompass.entitlements                      # MODIFIED: add App Group + Push Notifications capabilities
NeonCompassWidgets/                            # NEW target (WidgetKit extension)
  NeonCompassWidgets.entitlements              # NEW: same App Group
  NeonCompassWidgetsBundle.swift                # NEW: WidgetBundle entry point
  ProgressWidget.swift                          # NEW: TimelineProvider + widget view (progress ring + favorite cheat)
  WidgetSummary.swift                           # NEW: shared Codable struct written/read via the App Group

NeonCompass/Core/Widgets/
  WidgetSummaryWriting.swift                    # protocol
  AppGroupWidgetSummaryWriter.swift             # implementation, writes to shared UserDefaults + calls WidgetCenter.reloadTimelines

NeonCompass/Features/Progression/ProgressionModel.swift  # MODIFIED: writes summary on progress change
NeonCompass/Features/Cheats/CheatsModel.swift             # MODIFIED: writes summary on favorite change

NeonCompass/App/NeonCompassApp.swift            # MODIFIED: UIApplicationDelegateAdaptor for FCM/APNs
NeonCompass/App/AppDelegate.swift                # NEW: UIApplicationDelegate, FCM token registration

NeonCompass/Core/Notifications/
  FollowedCategoryNotifying.swift                # protocol
  FirebaseFollowedCategoryNotifier.swift          # implementation (permission request + FCM topic subscribe/unsubscribe)

NeonCompass/Features/Profile/FollowedCategoriesStore.swift  # NEW: @Observable, followed POICategory set + subscribe/unsubscribe
NeonCompass/Features/Profile/ProfileScreen.swift             # MODIFIED: followed-categories picker, Pro-gated

functions/src/notifyFollowedCategory.ts         # NEW: Firestore trigger on contributions/{id}, publishes to FCM topic on approval
functions/src/index.ts                           # MODIFIED: export

project.yml                                      # MODIFIED: new widget target, FirebaseMessaging product, App Group/Push entitlements
NeonCompass/Resources/Localizable.xcstrings       # MODIFIED: new strings

docs/ops/2026-07-23-widgets-and-push-setup.md    # NEW: manual Apple Developer portal + Firebase Console steps
```

---

### Task 1: WidgetKit extension + shared progress summary

**Files:**
- Modify: `project.yml`
- Modify: `NeonCompass.entitlements`
- Create: `NeonCompassWidgets/NeonCompassWidgets.entitlements`
- Create: `NeonCompassWidgets/NeonCompassWidgetsBundle.swift`
- Create: `NeonCompassWidgets/ProgressWidget.swift`
- Create: `NeonCompassWidgets/WidgetSummary.swift`
- Create: `NeonCompass/Core/Widgets/WidgetSummaryWriting.swift`
- Create: `NeonCompass/Core/Widgets/AppGroupWidgetSummaryWriter.swift`
- Modify: `NeonCompass/Features/Progression/ProgressionModel.swift`
- Modify: `NeonCompass/Features/Cheats/CheatsModel.swift`

**Interfaces:**
- Produces: `WidgetSummary: Codable` (`{isProEntitled: Bool, overallProgress: Double, favoriteCheatTitle: String?}`, shared between the app target and the widget extension — put this ONE file's content in a location both targets' `sources:` can include, see Step 1), `WidgetSummaryWriting` protocol (`func write(_ summary: WidgetSummary)`).

- [ ] **Step 1: Research XcodeGen's mechanism for adding a second (widget extension) target, and Apple's App Group entitlement requirements, before editing `project.yml`**

Use WebSearch/WebFetch to confirm: (1) XcodeGen's `targets:` spec for a `type: app-extension` / `platform: iOS` widget extension target, including the required `NSExtension` Info.plist keys (`NSExtensionPointIdentifier: com.apple.widgetkit-extension`) and how those get declared via XcodeGen (likely another `INFOPLIST_FILE`-merge or `INFOPLIST_KEY_*`/`info:` block, matching this project's established pattern from Plan 6a's `GADApplicationIdentifier` handling — verify rather than guess), (2) how a widget extension target depends on the main app target in XcodeGen (`dependencies: [{target: NeonCompass, embed: true}]`-style), (3) confirm `WidgetSummary.swift`'s content needs to be compiled into BOTH targets — the cleanest XcodeGen mechanism for a single source file included in two targets' `sources:` lists (do not duplicate the file on disk, reference the same path from both targets' source lists).

- [ ] **Step 2: Add the App Group entitlement to both targets**

Research the exact `com.apple.security.application-groups` entitlement key format. Both `NeonCompass.entitlements` (modify, add alongside the existing `com.apple.developer.applesignin` key) and the new `NeonCompassWidgets/NeonCompassWidgets.entitlements` need the SAME App Group identifier, e.g. `group.co.antoineteston.neoncompass` (matching this project's `bundleIdPrefix: co.antoineteston` from `project.yml`).

- [ ] **Step 3: Write `WidgetSummary.swift`**

```swift
import Foundation

/// The ONLY data a widget process ever sees — written by the main app to
/// a shared App Group UserDefaults suite, read by the widget extension's
/// TimelineProvider. Never a live SwiftData/Firestore query from the
/// widget process (Global Constraints: widgets never read SwiftData or
/// Firestore directly — a widget extension has no access to either).
struct WidgetSummary: Codable, Sendable {
    static let appGroupID = "group.co.antoineteston.neoncompass"
    static let userDefaultsKey = "widgetSummary"

    let isProEntitled: Bool
    let overallProgress: Double
    let favoriteCheatTitle: String?

    static func load() -> WidgetSummary? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSummary.self, from: data)
    }
}
```

- [ ] **Step 4: Write `WidgetSummaryWriting.swift` + `AppGroupWidgetSummaryWriter.swift`**

```swift
// NeonCompass/Core/Widgets/WidgetSummaryWriting.swift
protocol WidgetSummaryWriting: Sendable {
    func write(_ summary: WidgetSummary)
}
```

```swift
// NeonCompass/Core/Widgets/AppGroupWidgetSummaryWriter.swift
import Foundation
import WidgetKit

/// Writes to the App Group UserDefaults suite the widget extension reads
/// from, then asks WidgetKit to reload — without this call, a widget
/// already on the home screen keeps showing stale data until its next
/// system-scheduled refresh, which could be hours away.
final class AppGroupWidgetSummaryWriter: WidgetSummaryWriting {
    func write(_ summary: WidgetSummary) {
        guard let defaults = UserDefaults(suiteName: WidgetSummary.appGroupID),
              let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: WidgetSummary.userDefaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ProgressWidget")
    }
}
```

Verify `WidgetCenter.reloadTimelines(ofKind:)`'s exact signature/availability against current WidgetKit docs before finalizing — confirm whether it needs to run on the main actor.

- [ ] **Step 5: Wire the writer into `ProgressionModel` and `CheatsModel`**

Read both files in full (current state, post Plan 6b-2 for `ProgressionModel`). Add an optional `summaryWriter: WidgetSummaryWriting? = nil` parameter to each initializer, and call `summaryWriter?.write(...)` after `overallProgress`/`favoriteCheatIDs` changes — you'll need a way to compose the FULL `WidgetSummary` (which needs BOTH the progress number AND the favorite cheat title, from two different models) without either model knowing about the other. The simplest correct approach: don't compose from either model directly — add a small `WidgetSummaryCoordinator` (or similar) constructed once at `RootView` (matching the established shared-instance-via-environment pattern), injected into both `ProgressionModel` and `CheatsModel`, that each model calls with just its own piece (`coordinator.updateProgress(0.4)` / `coordinator.updateFavoriteCheat("Infinite ammo")`), and the coordinator itself holds both pieces of state and calls `WidgetSummaryWriting.write(...)` with the composed struct whenever either piece changes. Also needs `proEntitlementModel.isProEntitled` — inject that too (read-only access, the coordinator doesn't need the whole model, just the current boolean at write time, or hold a reference to `ProEntitlementModel` itself since it's already environment-shared).

- [ ] **Step 6: Write `ProgressWidget.swift` + `NeonCompassWidgetsBundle.swift`**

Verify the exact current WidgetKit API (`TimelineProvider`/`AppIntentTimelineProvider`, `StaticConfiguration`, `WidgetBundle`) against Apple's current docs before writing — WidgetKit's API has grown (Interactive widgets, `ControlWidget`, etc.) since its iOS 14 introduction; confirm the simplest static/non-interactive widget shape is still `StaticConfiguration` + a plain `TimelineProvider` for this iOS 26 target, not a newer required pattern.

```swift
// NeonCompassWidgets/ProgressWidget.swift — adapt to your Step 6 research
import WidgetKit
import SwiftUI

struct ProgressEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: .now, summary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: .now, summary: WidgetSummary.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: .now, summary: WidgetSummary.load())
        // Refresh hourly — this data doesn't change fast enough to justify
        // a tighter policy, and WidgetKit's own reload budget is limited.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct ProgressWidgetView: View {
    let entry: ProgressEntry

    var body: some View {
        if let summary = entry.summary, summary.isProEntitled {
            VStack(spacing: 8) {
                ProgressRing(progress: summary.overallProgress)
                    .frame(width: 44, height: 44)
                if let favoriteCheatTitle = summary.favoriteCheatTitle {
                    Text(favoriteCheatTitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .padding()
        } else {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("widget.upsell")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct ProgressWidget: Widget {
    let kind = "ProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    NCColor.nightSky
                }
        }
        .configurationDisplayName("widget.displayName")
        .description("widget.description")
        .supportedFamilies([.systemSmall])
    }
}
```

```swift
// NeonCompassWidgets/NeonCompassWidgetsBundle.swift
import WidgetKit
import SwiftUI

@main
struct NeonCompassWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ProgressWidget()
    }
}
```

`ProgressRing` (the existing view from Plan 6b-2/4's Progression screen) and `NCColor` need to be accessible from the widget target — confirm via your Step 1 research whether these specific source files need to be added to the widget target's `sources:` list too (a widget extension target is a separate compilation unit; it can't import the main app's module the way a unit test target can via `@testable import`). If `ProgressRing`/`NCColor` have no Firebase/UIKit-only dependencies that would break in a widget-extension context, include their source files directly in both targets' `sources:` (same file-sharing mechanism as `WidgetSummary.swift`); if they DO have app-only dependencies, write a minimal widget-local ring view instead rather than fighting cross-target dependency issues — note whichever choice you make and why in your report.

- [ ] **Step 7: Add Localizable.xcstrings entries**

| Key | EN value |
|---|---|
| `widget.displayName` | Neon Compass Progress |
| `widget.description` | Your collection progress and favorite cheat, at a glance. |
| `widget.upsell` | Unlock Pro for widgets |

- [ ] **Step 8: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **` for BOTH targets (the script may need a `-scheme`/destination check for the widget extension target — verify `Scripts/build.sh`'s actual invocation covers all targets, or note if a second build invocation is needed and add it).
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`, no regression (this task adds no new unit tests — WidgetKit's `TimelineProvider` isn't meaningfully unit-testable without a full widget host, consistent with how this codebase doesn't unit-test other UIKit/SwiftUI-bridging entry points).

- [ ] **Step 9: Commit**

```bash
git add project.yml NeonCompass.entitlements NeonCompassWidgets NeonCompass/Core/Widgets NeonCompass/Features/Progression/ProgressionModel.swift NeonCompass/Features/Cheats/CheatsModel.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: WidgetKit extension (progress ring + favorite cheat), shared via App Group summary"
```

---

### Task 2: Push notification core infra

**Files:**
- Create: `NeonCompass/App/AppDelegate.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`
- Modify: `NeonCompass.entitlements`
- Modify: `project.yml`
- Create: `NeonCompass/Core/Notifications/FollowedCategoryNotifying.swift`
- Create: `NeonCompass/Core/Notifications/FirebaseFollowedCategoryNotifier.swift`

**Interfaces:**
- Produces: `FollowedCategoryNotifying` protocol (`requestPermissionIfNeeded() async -> Bool`, `subscribe(to category: POICategory) async`, `unsubscribe(from category: POICategory) async`) — consumed by Task 3's `FollowedCategoriesStore`.

- [ ] **Step 1: Verify the current FirebaseMessaging + UNUserNotificationCenter API surface**

Use WebSearch/WebFetch (or, per this project's established practice, locate and inspect the resolved SPM package's actual Swift interface once linked) to confirm: `Messaging.messaging().subscribe(toTopic:)`/`.unsubscribe(fromTopic:)` signatures (completion-handler-based, likely with an auto-synthesized `async` overload — verify, don't assume, per this plan's own Task 1 caution and every SDK-facing task in Plans 6a/6b-1/6b-2), `UNUserNotificationCenter.current().requestAuthorization(options:)`'s exact signature, and how `UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` hands the APNs token to `Messaging.messaging().apnsToken`.

- [ ] **Step 2: Add `FirebaseMessaging` to `project.yml`**

```yaml
      - package: Firebase
        product: FirebaseMessaging
```

(Same `Firebase` package already linked, `FirebaseMessaging` is a sibling product — confirm this product name against the resolved package, matching this project's established SDK-verification discipline.)

- [ ] **Step 3: Add the Push Notifications entitlement**

```xml
<key>aps-environment</key>
<string>development</string>
```

Add to `NeonCompass.entitlements` (switch to `production` at release-build time — note this in Task 4's ops doc, don't hardcode a build-configuration-conditional value in this task without verifying XcodeGen supports per-configuration entitlement values; if it doesn't cleanly, `development` checked in with an ops-doc note about the release-time flip is an acceptable, disclosed simplification).

- [ ] **Step 4: Write `AppDelegate.swift`**

```swift
import UIKit
@preconcurrency import FirebaseMessaging

/// UIApplicationDelegate is required for APNs registration/FCM token
/// handoff — SwiftUI's App protocol has no direct hook for
/// didRegisterForRemoteNotificationsWithDeviceToken. Kept minimal:
/// nothing here does app setup that belongs in NeonCompassApp.init()
/// (FirebaseApp.configure() etc. stay there).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
```

Verify the exact method signatures against current UIKit/FirebaseMessaging APIs — this sketch is a starting point, per this plan's established verification discipline.

- [ ] **Step 5: Wire into `NeonCompassApp.swift`**

```swift
@main
struct NeonCompassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppCheck.setAppCheckProviderFactory(NeonCompassAppCheckProviderFactory())
        FirebaseApp.configure()
    }
    // ... rest unchanged
}
```

- [ ] **Step 6: Write `FollowedCategoryNotifying.swift` + `FirebaseFollowedCategoryNotifier.swift`**

```swift
// NeonCompass/Core/Notifications/FollowedCategoryNotifying.swift
protocol FollowedCategoryNotifying: Sendable {
    func requestPermissionIfNeeded() async -> Bool
    func subscribe(to category: POICategory) async
    func unsubscribe(from category: POICategory) async
}
```

```swift
// NeonCompass/Core/Notifications/FirebaseFollowedCategoryNotifier.swift
import UserNotifications
@preconcurrency import FirebaseMessaging

final class FirebaseFollowedCategoryNotifier: FollowedCategoryNotifying {
    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        if settings.authorizationStatus == .denied { return false }
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func subscribe(to category: POICategory) async {
        try? await Messaging.messaging().subscribe(toTopic: Self.topicName(for: category))
    }

    func unsubscribe(from category: POICategory) async {
        try? await Messaging.messaging().unsubscribe(fromTopic: Self.topicName(for: category))
    }

    private static func topicName(for category: POICategory) -> String {
        "spots-\(category.rawValue)"
    }
}
```

- [ ] **Step 7: Build and test**

Run: `Scripts/build.sh` — expect `** BUILD SUCCEEDED **`.
Run: `Scripts/test.sh` — expect `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/App/AppDelegate.swift NeonCompass/App/NeonCompassApp.swift NeonCompass.entitlements project.yml NeonCompass/Core/Notifications
git commit -m "feat: push notification core infra (AppDelegate/FCM registration, FollowedCategoryNotifying)"
```

---

### Task 3: Followed-categories UI + Cloud Function publish-on-approval

**Files:**
- Create: `NeonCompass/Features/Profile/FollowedCategoriesStore.swift`
- Create: `NeonCompassTests/Profile/FollowedCategoriesStoreTests.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Create: `functions/src/notifyFollowedCategory.ts`
- Modify: `functions/src/index.ts`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:** none consumed by later plans — this is the leaf feature closing out Plan 6b.

- [ ] **Step 1: Write `FollowedCategoriesStore.swift`**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class FollowedCategoriesStore {
    private static let followedKey = "followedCategories"
    private let defaults: UserDefaults
    private let notifier: FollowedCategoryNotifying

    private(set) var followedCategories: Set<POICategory>

    init(defaults: UserDefaults = .standard, notifier: FollowedCategoryNotifying) {
        self.defaults = defaults
        self.notifier = notifier
        let stored = defaults.stringArray(forKey: Self.followedKey) ?? []
        followedCategories = Set(stored.compactMap(POICategory.init(rawValue:)))
    }

    func toggle(_ category: POICategory) async {
        if followedCategories.contains(category) {
            followedCategories.remove(category)
            await notifier.unsubscribe(from: category)
        } else {
            let granted = await notifier.requestPermissionIfNeeded()
            guard granted else { return }
            followedCategories.insert(category)
            await notifier.subscribe(to: category)
        }
        defaults.set(followedCategories.map(\.rawValue), forKey: Self.followedKey)
    }
}
```

- [ ] **Step 2: Write `FollowedCategoriesStoreTests.swift`**

Follow the established `Fake*` convention (see `NeonCompassTests/Onboarding/OnboardingFakesTests.swift` for the exact style):

```swift
import Testing
@testable import NeonCompass
import Foundation

final class FakeFollowedCategoryNotifier: FollowedCategoryNotifying {
    nonisolated(unsafe) var permissionGranted = true
    nonisolated(unsafe) private(set) var subscribedCategories: Set<POICategory> = []

    func requestPermissionIfNeeded() async -> Bool { permissionGranted }
    func subscribe(to category: POICategory) async { subscribedCategories.insert(category) }
    func unsubscribe(from category: POICategory) async { subscribedCategories.remove(category) }
}

@MainActor
struct FollowedCategoriesStoreTests {
    @Test func toggleFollowsWhenPermissionGranted() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        #expect(store.followedCategories.contains(.collectible))
        #expect(notifier.subscribedCategories.contains(.collectible))
    }

    @Test func toggleDoesNothingWhenPermissionDenied() async {
        let notifier = FakeFollowedCategoryNotifier()
        notifier.permissionGranted = false
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
    }

    @Test func togglingAnAlreadyFollowedCategoryUnfollows() async {
        let notifier = FakeFollowedCategoryNotifier()
        let store = FollowedCategoriesStore(defaults: UserDefaults(suiteName: #function)!, notifier: notifier)
        await store.toggle(.collectible)
        await store.toggle(.collectible)
        #expect(!store.followedCategories.contains(.collectible))
        #expect(!notifier.subscribedCategories.contains(.collectible))
    }
}
```

- [ ] **Step 3: Wire into `ProfileScreen.swift`**

Read the current file in full (post Plan 6b-2's theme/icon additions). Add a `@State private var followedCategoriesStore: FollowedCategoriesStore?` (deferred construction, same pattern as `communityModel` in this same file — it doesn't need `FirebaseFollowedCategoryNotifier()`'s dependencies available at property-init time... actually it does, `FirebaseFollowedCategoryNotifier()` has a trivial parameterless init, so `@State private var followedCategoriesStore = FollowedCategoriesStore(notifier: FirebaseFollowedCategoryNotifier())` at property-init time is fine, no deferred construction needed here). Add a Pro-gated section with a toggle per `POICategory.allCases`, calling `await followedCategoriesStore.toggle(category)`.

- [ ] **Step 4: Add Localizable.xcstrings entries**

| Key | EN value |
|---|---|
| `profile.followedCategories.title` | Notify me about |

(Reuse the existing `map.category.*` keys for category names — don't duplicate them.)

- [ ] **Step 5: Write `notifyFollowedCategory.ts`**

```typescript
// functions/src/notifyFollowedCategory.ts
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { getMessaging } from 'firebase-admin/messaging';

// General/editorial notifications are explicitly out of scope and stay
// free (spec) — this only ever fires for a contribution transitioning
// INTO approved, never for editorial POI/guide/news publishes (a
// different content pipeline entirely, unaffected by this function).
export const notifyFollowedCategory = onDocumentUpdated(
  { region: 'europe-west1', document: 'contributions/{contributionId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === 'approved' || after.status !== 'approved') return;
    if (after.shadowHidden === true) return; // never notify about a shadow-hidden spot

    const category = after.category as string | undefined;
    if (!category) return;

    await getMessaging().send({
      topic: `spots-${category}`,
      notification: {
        title: 'notification.newSpot.title', // placeholder — real push payloads need pre-localized text per FCM's model, not a String Catalog key; see this task's Self-Review note
        body: after.title as string,
      },
    });
  }
);
```

Note the placeholder comment above is a genuine, disclosed simplification — FCM notification payloads are plain strings sent from the server, not String Catalog keys resolved on-device; proper localization of push copy requires either sending pre-localized text per recipient (needs per-user language stored server-side) or Apple's `loc-key`/`loc-args` APNs mechanism (which FCM does support passing through, but requires the exact right payload shape). Flag this as a known gap for a follow-up rather than half-implementing localized push in this task.

- [ ] **Step 6: Export from `index.ts`**

```typescript
export { notifyFollowedCategory } from './notifyFollowedCategory.js';
```

- [ ] **Step 7: Run tests**

Run: `cd functions && npm test` — expect existing tests to still pass, clean build (no new pure-logic unit test for this trigger — it's a thin Firestore-event handler, consistent with `flagSuspiciousContribution.ts` having no dedicated test either).
Run: `Scripts/build.sh` / `Scripts/test.sh` — expect `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`, including the new `FollowedCategoriesStoreTests` suite.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Features/Profile/FollowedCategoriesStore.swift NeonCompassTests/Profile/FollowedCategoriesStoreTests.swift NeonCompass/Features/Profile/ProfileScreen.swift functions/src/notifyFollowedCategory.ts functions/src/index.ts NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat: followed-category notifications (subscribe UI + Cloud Function publish-on-approval)"
```

---

### Task 4: Ops doc — Apple Developer portal + Firebase Console setup

**Files:**
- Create: `docs/ops/2026-07-23-widgets-and-push-setup.md`

- [ ] **Step 1: Write the ops doc**

```markdown
# Widgets & Push Notifications: manual setup steps

Not expressible in code — Apple Developer portal + Firebase Console
configuration. Spec §"Pro": "Widgets... Notifications suivies."

## 1. App ID capabilities (Apple Developer portal)

1. App Groups: enable on the main app's App ID, register
   `group.co.antoineteston.neoncompass` (must match `WidgetSummary.appGroupID`
   and both targets' entitlements files exactly).
2. Push Notifications: enable on the main app's App ID.
3. Regenerate/download provisioning profiles reflecting both new
   capabilities before the next TestFlight/device build — a stale
   profile will fail code signing with a capability mismatch, not a
   clear "you forgot a step" error.

## 2. APNs key (Firebase Console)

1. Apple Developer portal → Keys → create an APNs Authentication Key
   (one key covers all environments, unlike the older per-environment
   certificate model).
2. Firebase Console → Project Settings → Cloud Messaging → upload the
   APNs key (needs Key ID + Team ID).

## 3. `aps-environment` entitlement value at release

`NeonCompass.entitlements` (Task 2) ships `aps-environment: development`.
Before an App Store/TestFlight release build, this must be
`production` — confirm whether XcodeGen's build-configuration-scoped
entitlement values apply here, or whether this needs a manual flip in the
release branch/tag process. Document whichever mechanism is actually used
once decided (this plan defers that decision, see Task 2's own note).

## 4. Test the full push path

1. Follow a category in-app (Profile → Notify me about).
2. From the Firebase Console → Cloud Messaging → Send test message → topic
   `spots-<category>`, confirm delivery on a physical device (APNs/FCM
   don't reliably deliver to the Simulator).
3. Approve a real pending contribution of that category via
   `tools/content-cli moderate:approve <id>` (Plan 5c) and confirm the
   Cloud Function-triggered push arrives end-to-end, not just the manual
   test-message path.
```

- [ ] **Step 2: Commit**

```bash
git add docs/ops/2026-07-23-widgets-and-push-setup.md
git commit -m "docs: widgets + push notification manual setup checklist"
```

---

## Self-Review

**Spec coverage:**
- "Widgets écran d'accueil/verrouillé : anneau de progression, cheat favori épinglé (rendu accented Liquid Glass)" — Task 1. ⚠️ **Partial**: home-screen widget shipped; this plan does NOT add a Lock Screen widget family (`.accessoryCircular`/`.accessoryRectangular`) — spec says "écran d'accueil/verrouillé" (home AND lock screen). Deliberately scoped down to keep Task 1 a single, focused task; a Lock Screen widget variant is a small, natural follow-up (same `TimelineProvider`, an additional `WidgetFamily` case and view) once the home-screen widget is verified working, not a fundamentally different feature.
- "Notifications suivies : push quand un spot est publié dans une catégorie/zone suivie" — Tasks 2-3, category-only. ⚠️ **Zone-following explicitly deferred** — see Global Constraints, requires a geographic-boundary UI that doesn't exist.
- "les notifications générales restent gratuites" — this plan adds no general-notification gating of any kind, so nothing to gate. ✅

**Known simplifications, disclosed not silently shipped:**
- Lock Screen widget family and zone-following are both real spec requirements not fully delivered — flagged above, not silently dropped.
- Push notification body text is NOT localized (FCM payloads are plain server-sent strings, not String Catalog keys) — flagged in Task 3 Step 5 as a genuine gap requiring either per-user stored language or APNs `loc-key` plumbing, neither built here.
- `aps-environment`'s development-vs-production entitlement value at release time is deferred to the ops doc as an open question, not silently hardcoded and forgotten.
