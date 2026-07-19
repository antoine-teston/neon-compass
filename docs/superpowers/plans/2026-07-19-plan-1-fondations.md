# Plan 1 — Fondations (Neon Compass v1.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une app iOS/iPadOS qui compile et se lance : design system synthwave + Liquid Glass, navigation 5 onglets avec carte centrale proéminente, écran disclaimer au premier lancement.

**Architecture:** App SwiftUI feature-first (`App/`, `Features/`, `Core/`), projet généré par XcodeGen (le `.xcodeproj` n'est pas committé), aucune dépendance tierce dans ce plan. Les 5 onglets pointent vers des placeholders — les features arrivent dans les plans 2-6.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, Swift Testing, XcodeGen, iOS/iPadOS 26.

## Global Constraints

- Cible : iOS/iPadOS 26.0 minimum, iPhone + iPad (`TARGETED_DEVICE_FAMILY: 1,2`), pas de Mac Catalyst.
- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.
- Aucune marque Rockstar (GTA, Grand Theft Auto, Vice City, Leonida, Rockstar) dans le code, les identifiants, les strings ou les assets. Bundle ID : `co.antoineteston.neoncompass`.
- Toute string visible passe par le String Catalog (anglais = langue de développement) — pas de littéraux en dur dans les vues.
- SwiftUI uniquement ; UIKit seulement si une API l'impose, wrappé dans un fichier unique.
- Tests : Swift Testing (`import Testing`), jamais XCTest.
- Mode sombre uniquement ; glow limité à 3 accents par écran.
- Commandes de vérification :
  `xcodegen generate` puis
  `xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' build` (ou `test`).

---

### Task 1: Scaffolding du projet

**Files:**
- Create: `project.yml`, `.gitignore`, `NeonCompass/App/NeonCompassApp.swift`, `NeonCompass/App/RootView.swift`, `NeonCompass/Resources/Localizable.xcstrings`, `NeonCompassTests/SmokeTests.swift`

**Interfaces:**
- Produces: cible `NeonCompass` (app) + `NeonCompassTests` (unit tests), `RootView` (racine remplacée en Task 4).

- [ ] **Step 1: Vérifier XcodeGen**

Run: `which xcodegen || brew install xcodegen`

- [ ] **Step 2: Écrire `.gitignore`**

```gitignore
.DS_Store
xcuserdata/
DerivedData/
*.xcodeproj
.build/
```

- [ ] **Step 3: Écrire `project.yml`**

```yaml
name: NeonCompass
options:
  bundleIdPrefix: co.antoineteston
  deploymentTarget:
    iOS: "26.0"
  developmentLanguage: en
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    TARGETED_DEVICE_FAMILY: "1,2"
    INFOPLIST_KEY_UILaunchScreen_Generation: YES
    INFOPLIST_KEY_UIUserInterfaceStyle: Dark
targets:
  NeonCompass:
    type: application
    platform: iOS
    sources: [NeonCompass]
  NeonCompassTests:
    type: bundle.unit-test
    platform: iOS
    sources: [NeonCompassTests]
    dependencies:
      - target: NeonCompass
```

- [ ] **Step 4: Écrire l'app minimale**

`NeonCompass/App/NeonCompassApp.swift` :
```swift
import SwiftUI

@main
struct NeonCompassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`NeonCompass/App/RootView.swift` :
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Neon Compass")
    }
}
```

`NeonCompassTests/SmokeTests.swift` :
```swift
import Testing
@testable import NeonCompass

@Test func smokeTestTargetLinks() {
    #expect(Bool(true))
}
```

Créer aussi `NeonCompass/Resources/Localizable.xcstrings` avec un catalogue vide : `{"sourceLanguage":"en","strings":{},"version":"1.0"}`.

- [ ] **Step 5: Générer et builder**

Run: `xcodegen generate && xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add project.yml .gitignore NeonCompass NeonCompassTests
git commit -m "feat: scaffold NeonCompass app (XcodeGen, iOS 26, strict concurrency)"
```

---

### Task 2: Design system — couleurs, hex parsing, typographie

**Files:**
- Create: `NeonCompass/Core/DesignSystem/NCColor.swift`, `NeonCompass/Core/DesignSystem/NCTypography.swift`
- Test: `NeonCompassTests/DesignSystem/NCColorTests.swift`

**Interfaces:**
- Produces: `NCColor` (tokens statiques `nightSky`, `sunsetMagenta`, `sunsetViolet`, `sunsetOrange`, `neonCyan`, gradient `sunset`), `NCColor.RGBA.init?(hex: String)` → composants 0-1 (utilisé au plan 3 pour les couleurs de catégories venant de Firestore), `NCTypography.displayTitle`/`.body`.

- [ ] **Step 1: Écrire les tests du parser hex (failing)**

`NeonCompassTests/DesignSystem/NCColorTests.swift` :
```swift
import Testing
@testable import NeonCompass

struct NCColorTests {
    @Test func parsesSixDigitHex() {
        let c = NCColor.RGBA(hex: "#FF3388")
        #expect(c != nil)
        #expect(abs(c!.red - 1.0) < 0.001)
        #expect(abs(c!.green - 0.2) < 0.001)
        #expect(abs(c!.blue - 0.5333) < 0.001)
        #expect(c!.alpha == 1.0)
    }

    @Test func parsesWithoutHashAndLowercase() {
        #expect(NCColor.RGBA(hex: "1fe0e0") != nil)
    }

    @Test func rejectsInvalidHex() {
        #expect(NCColor.RGBA(hex: "#GGGGGG") == nil)
        #expect(NCColor.RGBA(hex: "#FFF") == nil)
        #expect(NCColor.RGBA(hex: "") == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: BUILD FAILED — `cannot find 'NCColor' in scope`

- [ ] **Step 3: Implémenter `NCColor`**

`NeonCompass/Core/DesignSystem/NCColor.swift` :
```swift
import SwiftUI

enum NCColor {
    static let nightSky = Color(RGBA(hex: "#0A081A")!)
    static let sunsetMagenta = Color(RGBA(hex: "#FF3388")!)
    static let sunsetViolet = Color(RGBA(hex: "#8C33F2")!)
    static let sunsetOrange = Color(RGBA(hex: "#FF8C40")!)
    static let neonCyan = Color(RGBA(hex: "#26F2F2")!)

    static let sunset = LinearGradient(
        colors: [sunsetMagenta, sunsetViolet, sunsetOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    struct RGBA: Equatable, Sendable {
        let red: Double, green: Double, blue: Double, alpha: Double

        init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1.0
        }
    }
}

extension Color {
    init(_ rgba: NCColor.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
```

`NeonCompass/Core/DesignSystem/NCTypography.swift` :
```swift
import SwiftUI

enum NCTypography {
    /// Titres d'écran uniquement — jamais le corps de texte.
    static let displayTitle = Font.system(size: 28, weight: .black, design: .rounded)
    static let body = Font.body
}
```

- [ ] **Step 4: Vérifier le succès**

Run: `xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **` (3 tests)

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/DesignSystem NeonCompassTests/DesignSystem
git commit -m "feat: design system tokens + hex color parser"
```

---

### Task 3: Modèle de navigation — AppTab et AppModel

**Files:**
- Create: `NeonCompass/App/AppTab.swift`, `NeonCompass/App/AppModel.swift`
- Test: `NeonCompassTests/App/AppTabTests.swift`

**Interfaces:**
- Produces: `enum AppTab: String, CaseIterable, Identifiable, Sendable` (cases dans l'ordre `feed, cheats, map, progress, profile` ; propriétés `titleKey: LocalizedStringKey`, `systemImage: String`) ; `@Observable final class AppModel` (`var selectedTab: AppTab`, init par défaut sur `.feed`). Consommé par Task 4 et tous les plans suivants.

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/App/AppTabTests.swift` :
```swift
import Testing
@testable import NeonCompass

struct AppTabTests {
    @Test func fiveTabsWithMapInCenter() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs[2] == .map)
        #expect(tabs.first == .feed)
    }

    @Test func defaultTabIsFeed() {
        #expect(AppModel().selectedTab == .feed)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: BUILD FAILED — `cannot find 'AppTab' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/App/AppTab.swift` :
```swift
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, cheats, map, progress, profile

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: "tab.feed"
        case .cheats: "tab.cheats"
        case .map: "tab.map"
        case .progress: "tab.progress"
        case .profile: "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "newspaper"
        case .cheats: "gamecontroller"
        case .map: "map.fill"
        case .progress: "chart.pie"
        case .profile: "person.crop.circle"
        }
    }
}
```

`NeonCompass/App/AppModel.swift` :
```swift
import Observation

@Observable
@MainActor
final class AppModel {
    var selectedTab: AppTab = .feed
}
```

Note : `AppModel().selectedTab` étant `@MainActor`, annoter les tests `@MainActor` si le compilateur l'exige :
```swift
@Test @MainActor func defaultTabIsFeed() { ... }
```

- [ ] **Step 4: Vérifier le succès**

Run: `xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/App NeonCompassTests/App
git commit -m "feat: AppTab + AppModel navigation model"
```

---

### Task 4: RootView — TabView adaptative avec carte centrale

**Files:**
- Modify: `NeonCompass/App/RootView.swift`
- Create: `NeonCompass/App/PlaceholderScreen.swift`, `NeonCompass/App/CompactTabBar.swift`

**Interfaces:**
- Consumes: `AppTab`, `AppModel`, `NCColor`, `NCTypography` (Tasks 2-3).
- Produces: `RootView` finale (les plans 2-6 remplacent chaque `PlaceholderScreen` par la vraie feature) ; `CompactTabBar(selection: Binding<AppTab>)`.

- [ ] **Step 1: Implémenter les placeholders**

`NeonCompass/App/PlaceholderScreen.swift` :
```swift
import SwiftUI

struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(NCColor.sunset)
                Text(tab.titleKey)
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
            }
        }
    }
}
```

- [ ] **Step 2: Implémenter la barre compacte à bouton central**

`NeonCompass/App/CompactTabBar.swift` :
```swift
import SwiftUI

/// Barre iPhone : 5 items, carte en bouton central proéminent.
/// Sur iPad, RootView utilise la TabView système (sidebarAdaptable).
struct CompactTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                ForEach(AppTab.allCases) { tab in
                    if tab == .map {
                        mapButton
                    } else {
                        tabButton(tab)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 12)
    }

    private var mapButton: some View {
        Button {
            selection = .map
        } label: {
            Image(systemName: AppTab.map.systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
        }
        .glassEffect(.regular.tint(NCColor.sunsetMagenta.opacity(0.6)).interactive(), in: .circle)
        .offset(y: -12)
        .accessibilityLabel(Text(AppTab.map.titleKey))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20))
                Text(tab.titleKey)
                    .font(.caption2)
            }
            .foregroundStyle(selection == tab ? NCColor.neonCyan : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular.interactive())
    }
}
```

- [ ] **Step 3: Réécrire `RootView`**

`NeonCompass/App/RootView.swift` :
```swift
import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            PlaceholderScreen(tab: model.selectedTab)
            CompactTabBar(selection: $model.selectedTab)
        }
    }

    private var regularLayout: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    PlaceholderScreen(tab: tab)
                } label: {
                    Label(tab.titleKey, systemImage: tab.systemImage)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
```

- [ ] **Step 4: Ajouter les strings des onglets au String Catalog**

Dans `NeonCompass/Resources/Localizable.xcstrings`, ajouter `tab.feed` = "News", `tab.cheats` = "Cheats", `tab.map` = "Map", `tab.progress` = "Progress", `tab.profile` = "Profile" (langue source EN ; les 4 autres langues arrivent au plan 6).

- [ ] **Step 5: Builder, lancer, vérifier visuellement**

Run: `xcodegen generate && xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **`
Puis lancement simulateur (iPhone 16 **et** iPad) : 5 onglets, bouton carte central surélevé en verre teinté sur iPhone, sidebar adaptative sur iPad, fond nuit + placeholders néon.

- [ ] **Step 6: Commit**

```bash
git add NeonCompass/App NeonCompass/Resources
git commit -m "feat: adaptive root navigation with prominent center map button"
```

---

### Task 5: Onboarding disclaimer

**Files:**
- Create: `NeonCompass/Features/Onboarding/OnboardingModel.swift`, `NeonCompass/Features/Onboarding/DisclaimerView.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Test: `NeonCompassTests/Onboarding/OnboardingModelTests.swift`

**Interfaces:**
- Consumes: `NCColor`, `NCTypography`.
- Produces: `@Observable @MainActor final class OnboardingModel` (`init(defaults: UserDefaults = .standard)`, `var needsDisclaimer: Bool`, `func acceptDisclaimer()`) — réutilisé au plan 6 pour ATT/UMP (l'onboarding devient séquentiel).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Onboarding/OnboardingModelTests.swift` :
```swift
import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct OnboardingModelTests {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    @Test func needsDisclaimerOnFirstLaunch() {
        let model = OnboardingModel(defaults: freshDefaults())
        #expect(model.needsDisclaimer)
    }

    @Test func acceptPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let model = OnboardingModel(defaults: defaults)
        model.acceptDisclaimer()
        #expect(!model.needsDisclaimer)
        #expect(!OnboardingModel(defaults: defaults).needsDisclaimer)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: BUILD FAILED — `cannot find 'OnboardingModel' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Features/Onboarding/OnboardingModel.swift` :
```swift
import Foundation
import Observation

@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private let defaults: UserDefaults
    var needsDisclaimer: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        needsDisclaimer = false
    }
}
```

`NeonCompass/Features/Onboarding/DisclaimerView.swift` :
```swift
import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(NCColor.sunset)
                Text("disclaimer.title")
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)
                Text("disclaimer.body")
                    .font(NCTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button("disclaimer.accept", action: onAccept)
                    .buttonStyle(.glassProminent)
                    .tint(NCColor.sunsetMagenta)
                    .padding(.bottom, 40)
            }
        }
    }
}
```

Dans `RootView`, présenter le disclaimer tant qu'il n'est pas accepté :
```swift
struct RootView: View {
    @State private var model = AppModel()
    @State private var onboarding = OnboardingModel()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .preferredColorScheme(.dark)
    }
    // compactLayout / regularLayout inchangés (Task 4)
}
```

Strings à ajouter au String Catalog : `disclaimer.title` = "Unofficial companion", `disclaimer.body` = "This app is a fan project. It is not affiliated with, endorsed by, or connected to Rockstar Games or Take-Two Interactive. All artwork is original.", `disclaimer.accept` = "Got it".

- [ ] **Step 4: Vérifier le succès**

Run: `xcodebuild -project NeonCompass.xcodeproj -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **` — puis lancement simulateur : disclaimer au premier lancement, plus jamais ensuite.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Onboarding NeonCompassTests/Onboarding NeonCompass/App/RootView.swift NeonCompass/Resources
git commit -m "feat: first-launch disclaimer with persisted acceptance"
```
