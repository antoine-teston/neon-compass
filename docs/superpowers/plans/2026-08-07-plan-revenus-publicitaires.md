# Revenus publicitaires — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rendre encaissables les revenus publicitaires — vrais identifiants sous garde Debug/Release, interstitiel déjà écrit enfin déclenché, et demande ATT déplacée après le consentement RGPD et après un premier usage.

**Architecture:** trois chantiers indépendants qui se suivent. Un `AdUnits` centralise les identifiants derrière un `#if DEBUG` qu'un test verrouille. Un `InterstitialCoordinator` `@Observable` devient le seul endroit qui décide de montrer une pleine page — les écrans n'ont qu'une entrée, `contentConsumed()`, et ne peuvent pas oublier la garde Pro. `OnboardingModel` inverse l'ordre de ses portes et cesse de jeter le booléen de consentement que `ConsentProviding` lui rend déjà.

**Tech Stack:** Swift 6 (concurrence stricte), SwiftUI, Observation, Swift Testing, GoogleMobileAds 13.x, UMP 3.x, XcodeGen.

## Global Constraints

- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`. Aucun `@unchecked Sendable` ajouté.
- SwiftUI seulement. Aucun UIKit nouveau hors de ce qui existe déjà dans `Core/Ads/`.
- Tests en Swift Testing (`import Testing`), jamais XCTest.
- Toute chaîne affichée passe par le String Catalog. Langue de base : `en`.
- Aucun onglet n'a de `NavigationStack` : un `ToolbarItem` posé sur un écran d'onglet ne s'affiche nulle part.
- **Relancer `xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- `xcodebuild test` peut réécrire `NeonCompass/Resources/Localizable.xcstrings`. Vérifier `git status` avant chaque commit et restaurer le fichier s'il apparaît modifié sans qu'on y ait touché.
- Simulateur : `iPhone 17`.

Commandes de référence :

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AdUnitsTests
```

---

### Task 1 : `AdUnits`, la garde qui rend l'accident impossible

**Files:**
- Create: `NeonCompass/Core/Ads/AdUnits.swift`
- Test: `NeonCompassTests/Ads/AdUnitsTests.swift`
- Modify: `NeonCompass/Core/Ads/BannerAdView.swift:64`
- Modify: `NeonCompass/Core/Ads/AdMobInterstitialProvider.swift:53`
- Modify: `NeonCompass/Support/Info-Ads.plist`
- Modify: `project.yml` (bloc `targets.NeonCompass.settings.configs`)

**Interfaces:**
- Produces: `enum AdUnits` avec `static let banner: String`, `static let interstitial: String`, et `enum AdUnits.Test` portant `banner` / `interstitial`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `NeonCompassTests/Ads/AdUnitsTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct AdUnitsTests {
    /// Les tests tournent en Debug. Si quelqu'un place un identifiant réel dans
    /// la branche Debug, cette assertion tombe — AVANT que le simulateur ne
    /// produise du trafic invalide et ne fasse suspendre le compte AdMob.
    /// C'est le seul test de ce plan dont l'absence coûterait un compte.
    @Test func debugBuildsOnlyEverUseGoogleTestUnits() {
        #expect(AdUnits.banner == AdUnits.Test.banner)
        #expect(AdUnits.interstitial == AdUnits.Test.interstitial)
    }

    /// Le préfixe éditeur des unités de test publiques de Google. L'affirmer
    /// évite qu'une faute de frappe dans un identifiant de test passe pour un
    /// identifiant valide : une unité inexistante ne remplit jamais, et le
    /// symptôme serait « la bannière ne s'affiche plus », pas « mauvais ID ».
    @Test func testUnitsCarryGooglesPublicPublisherPrefix() {
        #expect(AdUnits.Test.banner.hasPrefix("ca-app-pub-3940256099942544/"))
        #expect(AdUnits.Test.interstitial.hasPrefix("ca-app-pub-3940256099942544/"))
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AdUnitsTests
```

Attendu : ÉCHEC de compilation, `cannot find 'AdUnits' in scope`.

- [ ] **Step 3: Écrire `AdUnits`**

Créer `NeonCompass/Core/Ads/AdUnits.swift` :

```swift
import Foundation

/// Les identifiants d'unité publicitaire, et la garantie qu'aucune vraie
/// publicité n'est servie en développement.
///
/// **Pourquoi une indirection plutôt que deux constantes remplacées le jour J.**
/// La règle AdMob interdit de servir et de cliquer de vraies annonces pendant le
/// développement : chaque lancement en simulateur deviendrait du trafic
/// invalide, et la sanction est la suspension du compte. Un remplacement
/// inconditionnel des identifiants de test — le « TODO » que portaient
/// `BannerAdView` et `AdMobInterstitialProvider` — est donc un piège à retardement.
/// La séparation doit exister AVANT que les vrais identifiants n'arrivent.
///
/// **Pourquoi pas d'xcconfig ni de trousseau.** Ces identifiants ne sont pas des
/// secrets : ils sont lisibles dans le binaire de n'importe quelle app publiée.
/// Les cacher serait de la cérémonie sans bénéfice.
enum AdUnits {
    /// Les unités de test publiquement documentées par Google.
    /// https://developers.google.com/admob/ios/test-ads
    enum Test {
        static let banner = "ca-app-pub-3940256099942544/2934735716"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    }

    #if DEBUG
    static let banner = Test.banner
    static let interstitial = Test.interstitial
    #else
    // TODO(ops) : remplacer par les unités réelles à la création du compte AdMob.
    // Tant qu'elles valent les unités de test, une Release ne rapporte rien —
    // c'est visible dans la console AdMob, et c'est le bon défaut : zéro revenu
    // vaut mieux qu'un compte suspendu.
    static let banner = Test.banner
    static let interstitial = Test.interstitial
    #endif
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AdUnitsTests
```

Attendu : SUCCÈS, 2 tests.

- [ ] **Step 5: Prouver que le test sait échouer**

Remplacer temporairement, dans la branche `#if DEBUG` d'`AdUnits`, `static let banner = Test.banner` par `static let banner = "ca-app-pub-0000000000000000/1111111111"`. Relancer la commande du Step 4.

Attendu : ÉCHEC sur `debugBuildsOnlyEverUseGoogleTestUnits`. **Rétablir la ligne** et relancer pour revenir au vert. Un contrôle qui ne sait qu'approuver est indiscernable d'un bon.

- [ ] **Step 6: Brancher les deux appelants**

Dans `NeonCompass/Core/Ads/BannerAdView.swift`, remplacer la ligne 64 :

```swift
    var adUnitID: String = "ca-app-pub-3940256099942544/2934735716" // AdMob's public test adaptive-banner ID — replace once provisioned.
```

par :

```swift
    var adUnitID: String = AdUnits.banner
```

Dans `NeonCompass/Core/Ads/AdMobInterstitialProvider.swift`, remplacer la ligne 53 :

```swift
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910" // AdMob's public test interstitial ID — replace with the real unit ID once provisioned in the AdMob console (same TODO pattern as Task 1's GADApplicationIdentifier placeholder).
```

par :

```swift
    private static let adUnitID = AdUnits.interstitial
```

- [ ] **Step 7: Sortir l'App ID du fichier de propriétés**

Dans `NeonCompass/Support/Info-Ads.plist`, remplacer le bloc `GADApplicationIdentifier` par :

```xml
	<!-- Valeur fournie par configuration (project.yml → settings.configs), parce
	     qu'un fichier de propriétés ne peut pas porter de `#if DEBUG`. Voir
	     Core/Ads/AdUnits.swift pour la même séparation côté unités. -->
	<key>GADApplicationIdentifier</key>
	<string>$(GAD_APP_ID)</string>
```

Dans `project.yml`, remplacer le bloc `configs` de la cible `NeonCompass` par :

```yaml
      configs:
        # Expose le dossier Documents dans l'app Fichiers, pour récupérer les
        # brouillons du mode éditeur sans compte ni base distante. DEBUG seulement :
        # l'app publiée n'a aucune raison d'ouvrir son dossier au monde.
        Debug:
          INFOPLIST_KEY_UIFileSharingEnabled: YES
          INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace: YES
          # App ID de TEST de Google. Il doit rester cohérent avec les unités de
          # AdUnits : un App ID de test avec une unité réelle ne sert rien et
          # n'échoue pas bruyamment.
          GAD_APP_ID: "ca-app-pub-3940256099942544~1458002511"
        Release:
          # TODO(ops) : remplacer par l'App ID réel à la création du compte AdMob.
          GAD_APP_ID: "ca-app-pub-3940256099942544~1458002511"
```

- [ ] **Step 8: Vérifier que l'App ID atterrit bien dans le binaire**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Puis lire la valeur effectivement écrite :

```sh
plutil -extract GADApplicationIdentifier raw \
  "$(xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
     -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/NeonCompass.app/Info.plist"
```

Attendu : `ca-app-pub-3940256099942544~1458002511`.
Si la sortie contient littéralement `$(GAD_APP_ID)`, la substitution n'a pas eu lieu — ne pas continuer, corriger d'abord.

- [ ] **Step 9: Suite complète, puis commit**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
git status --short   # Localizable.xcstrings ne doit PAS apparaître
git add NeonCompass/Core/Ads/AdUnits.swift NeonCompassTests/Ads/AdUnitsTests.swift \
        NeonCompass/Core/Ads/BannerAdView.swift NeonCompass/Core/Ads/AdMobInterstitialProvider.swift \
        NeonCompass/Support/Info-Ads.plist project.yml
git commit -m "feat(pub): les identifiants réels ne peuvent plus fuiter en développement"
```

---

### Task 2 : `InterstitialSession`, la session qui se réarme

**Files:**
- Create: `NeonCompass/Core/Ads/InterstitialSession.swift`
- Test: `NeonCompassTests/Ads/InterstitialSessionTests.swift`

**Interfaces:**
- Produces: `struct InterstitialSession` avec `init()`, `var shownCount: Int { get }`, `mutating func recordShown()`, `mutating func didEnterBackground(at: Date)`, `mutating func willEnterForeground(at: Date)`, et `static let resetThreshold: TimeInterval`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Ads/InterstitialSessionTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

struct InterstitialSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func aFreshSessionHasShownNothing() {
        #expect(InterstitialSession().shownCount == 0)
    }

    @Test func recordingAShowIncrementsTheCount() {
        var session = InterstitialSession()
        session.recordShown()
        #expect(session.shownCount == 1)
    }

    /// Le cas iPad : la tablette posée à côté de la télé toute la soirée. Le
    /// processus ne meurt jamais, donc sans ce réarmement « un par session »
    /// deviendrait « un par jour ».
    @Test func fiveMinutesInBackgroundRearmsTheCounter() {
        var session = InterstitialSession()
        session.recordShown()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(300))
        #expect(session.shownCount == 0)
    }

    @Test func fourMinutesFiftyNineSecondsDoesNotRearm() {
        var session = InterstitialSession()
        session.recordShown()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(299))
        #expect(session.shownCount == 1)
    }

    /// Un retour au premier plan sans passage par l'arrière-plan ne doit rien
    /// réarmer : sinon le premier `willEnterForeground` du lancement remettrait
    /// à zéro un compteur déjà à zéro, et surtout n'importe quel événement de
    /// cycle de vie parasite offrirait un interstitiel de plus.
    @Test func returningToForegroundWithoutHavingBackgroundedDoesNothing() {
        var session = InterstitialSession()
        session.recordShown()
        session.willEnterForeground(at: start.addingTimeInterval(10_000))
        #expect(session.shownCount == 1)
    }

    /// Le séjour est CONSOMMÉ par le premier retour. Sans cela, un second
    /// `willEnterForeground` rejouerait le même vieux séjour et réarmerait une
    /// session qui vient à peine de commencer.
    @Test func aBackgroundStayIsConsumedByTheFirstReturn() {
        var session = InterstitialSession()
        session.didEnterBackground(at: start)
        session.willEnterForeground(at: start.addingTimeInterval(300))
        session.recordShown()
        session.willEnterForeground(at: start.addingTimeInterval(600))
        #expect(session.shownCount == 1)
    }
}
```

- [ ] **Step 2: Lancer les tests et vérifier qu'ils échouent**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialSessionTests
```

Attendu : ÉCHEC de compilation, `cannot find 'InterstitialSession' in scope`.

- [ ] **Step 3: Écrire `InterstitialSession`**

Créer `NeonCompass/Core/Ads/InterstitialSession.swift` :

```swift
import Foundation

/// Le comptage des interstitiels d'une session — et surtout, la définition de
/// « session ».
///
/// **Le piège que ce type corrige.** Le plafond de la spec vaut « un par
/// session », et le compteur vivait en mémoire : la session, c'était donc la vie
/// du processus. Or le cas d'usage phare de l'iPad est la tablette posée à côté
/// de la télé toute la soirée — le processus ne meurt jamais, et « un par
/// session » devenait « un par jour ». Une session est ici une période au
/// premier plan, réarmée après un séjour d'au moins `resetThreshold` en
/// arrière-plan.
///
/// L'horloge est passée en paramètre plutôt que lue : tout est vérifiable sans
/// attendre cinq minutes, et le type reste pur.
struct InterstitialSession: Equatable, Sendable {
    /// Cinq minutes : la convention d'usage pour découper des sessions
    /// analytiques. Assez long pour qu'un aller-retour vers Messages ne
    /// réarme rien, assez court pour qu'une vraie pause compte.
    static let resetThreshold: TimeInterval = 5 * 60

    private(set) var shownCount = 0

    /// L'instant du dernier passage en arrière-plan, tant qu'il n'a pas été
    /// consommé par un retour.
    private var backgroundedAt: Date?

    init() {}

    mutating func recordShown() {
        shownCount += 1
    }

    mutating func didEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    mutating func willEnterForeground(at date: Date) {
        // Consommé quoi qu'il arrive : un séjour ne vaut que pour le retour qui
        // le suit immédiatement.
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return }
        guard date.timeIntervalSince(backgroundedAt) >= Self.resetThreshold else { return }
        shownCount = 0
    }
}
```

- [ ] **Step 4: Lancer les tests et vérifier qu'ils passent**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialSessionTests
```

Attendu : SUCCÈS, 6 tests.

- [ ] **Step 5: Prouver que le seuil sait échouer**

Remplacer temporairement `>= Self.resetThreshold` par `>= 0` dans `willEnterForeground`. Relancer le Step 4.

Attendu : ÉCHEC sur `fourMinutesFiftyNineSecondsDoesNotRearm`. **Rétablir** et revérifier le vert.

- [ ] **Step 6: Commit**

```sh
git status --short
git add NeonCompass/Core/Ads/InterstitialSession.swift NeonCompassTests/Ads/InterstitialSessionTests.swift
git commit -m "feat(pub): une session d'interstitiel se réarme, l'iPad cesse d'en voir un par jour"
```

---

### Task 3 : `serverFrequency` — le renommage que le code réclamait, et sa source

**Files:**
- Create: `NeonCompass/Core/Ads/InterstitialFrequencyGate.swift`
- Test: `NeonCompassTests/Ads/InterstitialFrequencyGateTests.swift`
- Modify: `NeonCompass/Core/Ads/InterstitialCapPolicy.swift`
- Modify: `NeonCompassTests/Ads/InterstitialCapPolicyTests.swift`
- Modify: `NeonCompass/Core/Config/SupabaseAppConfig.swift` (enum `AppConfigKey`)

**Interfaces:**
- Consumes: `AppConfigReading.int(_:) async throws -> Int?` et `AppConfigKey` (existants, `Core/Config/SupabaseAppConfig.swift`).
- Produces: `protocol InterstitialFrequencyProviding: Sendable { func frequency() async -> Int }`, `struct SupabaseInterstitialFrequencyGate` avec `static let defaultFrequency = 1`, et `AppConfigKey.interstitialFrequency`.
- Produces: `InterstitialCapPolicy.shouldShow(sessionShownCount:isDuringContribution:serverFrequency:)` — troisième étiquette renommée.

- [ ] **Step 1: Renommer le paramètre dans les tests existants**

Dans `NeonCompassTests/Ads/InterstitialCapPolicyTests.swift`, remplacer les cinq occurrences de `remoteConfigFrequency:` par `serverFrequency:`, et renommer le test `remoteConfigZeroDisablesInterstitialsEntirely` en `serverFrequencyZeroDisablesInterstitialsEntirely`.

- [ ] **Step 2: Ajouter le test de la porte de fréquence**

Créer `NeonCompassTests/Ads/InterstitialFrequencyGateTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

/// Doublure locale d'`AppConfigReading`. Les trois cas qui comptent — absent,
/// présent, illisible — sont exactement ceux que le protocole distingue, et
/// aucun ne demande de réseau.
private struct StubAppConfig: AppConfigReading {
    var intValue: Int?
    var throwsOnRead = false

    func bool(_ key: String, default defaultValue: Bool) async throws -> Bool {
        defaultValue
    }

    func string(_ key: String) async throws -> String? { nil }

    func int(_ key: String) async throws -> Int? {
        if throwsOnRead { throw URLError(.notConnectedToInternet) }
        return intValue
    }
}

struct InterstitialFrequencyGateTests {
    @Test func anExplicitValueIsUsedAsIs() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: 0))
        #expect(await gate.frequency() == 0)
    }

    /// Aucune ligne pour la clé : le format reste actif. Ce défaut est OUVERT,
    /// à l'inverse de `SupabaseServerFeatureGate` — celui-ci décrit une capacité
    /// qui existe déjà, pas une qui n'est pas déployée.
    @Test func anAbsentKeyLeavesInterstitialsOn() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: nil))
        #expect(await gate.frequency() == SupabaseInterstitialFrequencyGate.defaultFrequency)
    }

    /// Une coupure réseau ne doit pas éteindre un format qui fonctionne : ce
    /// serait couper le revenu au moment précis où le réseau est mauvais.
    @Test func anUnreadableConfigLeavesInterstitialsOn() async {
        let gate = SupabaseInterstitialFrequencyGate(config: StubAppConfig(intValue: 3, throwsOnRead: true))
        #expect(await gate.frequency() == SupabaseInterstitialFrequencyGate.defaultFrequency)
    }
}
```

- [ ] **Step 3: Lancer et vérifier l'échec**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialFrequencyGateTests
```

Attendu : ÉCHEC de compilation, `cannot find 'SupabaseInterstitialFrequencyGate' in scope`.

- [ ] **Step 4: Renommer le paramètre de la politique**

Dans `NeonCompass/Core/Ads/InterstitialCapPolicy.swift`, remplacer le bloc de documentation du troisième paramètre et sa signature. Le paragraphe qui annonçait le renommage disparaît — c'est ce branchement-là :

```swift
    ///   - serverFrequency: la fréquence pilotée par `app_config` — 0 éteint
    ///     entièrement les interstitiels (coupe-circuit), 1 signifie « éligible »
    ///     sous réserve du plafond de session ci-dessous, et les valeurs
    ///     supérieures à 1 sont réservées à un futur schéma « un sur N moments
    ///     éligibles » qui n'existe pas encore et sont donc traitées comme 1.
    static func shouldShow(
        sessionShownCount: Int,
        isDuringContribution: Bool,
        serverFrequency: Int
    ) -> Bool {
        guard serverFrequency > 0 else { return false }
        guard !isDuringContribution else { return false }
        return sessionShownCount < 1
    }
```

- [ ] **Step 5: Écrire la porte de fréquence**

Dans `NeonCompass/Core/Config/SupabaseAppConfig.swift`, ajouter une clé à `AppConfigKey` :

```swift
    static let interstitialFrequency = "interstitialFrequency"
```

Créer `NeonCompass/Core/Ads/InterstitialFrequencyGate.swift` :

```swift
import Foundation

/// La fréquence d'interstitiel, pilotée depuis `app_config`.
///
/// Zéro est le coupe-circuit : il éteint le format sans mise à jour de l'app.
///
/// **Défaut OUVERT**, comme le coupe-circuit communautaire et à l'inverse de
/// `SupabaseServerFeatureGate`. Ce dernier décrit une capacité qui n'existe pas
/// encore et doit donc échouer fermé ; celui-ci éteint une capacité qui existe,
/// et une coupure réseau ne doit pas l'éteindre — ce serait couper le revenu au
/// moment précis où le réseau est mauvais.
protocol InterstitialFrequencyProviding: Sendable {
    func frequency() async -> Int
}

struct SupabaseInterstitialFrequencyGate: InterstitialFrequencyProviding {
    static let defaultFrequency = 1

    private let config: any AppConfigReading

    init(config: any AppConfigReading = SupabaseAppConfig.shared) {
        self.config = config
    }

    func frequency() async -> Int {
        // Deux niveaux d'optionnel à défaire, et ils ne disent pas la même
        // chose : `try?` avale l'illisible, l'optionnel intérieur signale
        // l'absence de ligne. Les deux retombent ici sur le même défaut, mais
        // les distinguer garde la porte lisible si l'un des deux devait changer.
        guard let read = try? await config.int(AppConfigKey.interstitialFrequency),
              let frequency = read else { return Self.defaultFrequency }
        return frequency
    }
}
```

- [ ] **Step 6: Lancer et vérifier le vert**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialFrequencyGateTests
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialCapPolicyTests
```

Attendu : SUCCÈS, 3 tests puis 5 tests.

- [ ] **Step 7: Commit**

```sh
git status --short
git add NeonCompass/Core/Ads/InterstitialFrequencyGate.swift NeonCompass/Core/Ads/InterstitialCapPolicy.swift \
        NeonCompass/Core/Config/SupabaseAppConfig.swift \
        NeonCompassTests/Ads/InterstitialFrequencyGateTests.swift NeonCompassTests/Ads/InterstitialCapPolicyTests.swift
git commit -m "refactor(pub): la fréquence ne s'appelle plus Remote Config, et vient d'app_config"
```

---

### Task 4 : `InterstitialCoordinator` et les deux sites d'appel

**Files:**
- Create: `NeonCompass/Core/Ads/InterstitialCoordinator.swift`
- Test: `NeonCompassTests/Ads/InterstitialCoordinatorTests.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompass/Features/Feed/FeedListView.swift:43`
- Modify: `NeonCompass/Features/Cheats/CheatsScreen.swift:50`

**Interfaces:**
- Consumes: `InterstitialAdProviding` (existant), `InterstitialSession` (Task 2), `InterstitialFrequencyProviding` et `InterstitialCapPolicy.shouldShow(sessionShownCount:isDuringContribution:serverFrequency:)` (Task 3).
- Produces: `@Observable @MainActor final class InterstitialCoordinator` avec `init(provider:frequencyGate:isProEntitled:now:)`, `func contentConsumed() async`, `func refreshFrequency() async`, `func didEnterBackground()`, `func willEnterForeground()`, et `var isDuringContribution: Bool`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Ads/InterstitialCoordinatorTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

/// Doublure d'`InterstitialAdProviding`. Compte les présentations plutôt que de
/// les simuler : ce qui est vérifié ici est une décision, pas un rendu.
private final class SpyInterstitialProvider: InterstitialAdProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _loadCount = 0
    private var _showCount = 0
    private var _isReady: Bool
    private let loadSucceeds: Bool

    init(isReadyInitially: Bool = false, loadSucceeds: Bool = true) {
        _isReady = isReadyInitially
        self.loadSucceeds = loadSucceeds
    }

    var loadCount: Int { lock.withLock { _loadCount } }
    var showCount: Int { lock.withLock { _showCount } }
    var isReady: Bool { lock.withLock { _isReady } }

    func load() async throws {
        lock.withLock { _loadCount += 1 }
        guard loadSucceeds else { throw URLError(.timedOut) }
        lock.withLock { _isReady = true }
    }

    @MainActor func show() async -> Bool {
        guard isReady else { return false }
        lock.withLock {
            _showCount += 1
            _isReady = false
        }
        return true
    }
}

private struct StubFrequency: InterstitialFrequencyProviding {
    var value: Int
    func frequency() async -> Int { value }
}

@MainActor
struct InterstitialCoordinatorTests {
    private func makeCoordinator(
        provider: SpyInterstitialProvider,
        frequency: Int = 1,
        isPro: Bool = false
    ) -> InterstitialCoordinator {
        InterstitialCoordinator(
            provider: provider,
            frequencyGate: StubFrequency(value: frequency),
            isProEntitled: { isPro },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
    }

    @Test func aConsumedDetailShowsOneInterstitial() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 1)
    }

    /// La garde vit ICI et nulle part ailleurs : aucun site d'appel ne la
    /// connaît, donc aucun ne peut l'oublier. C'est la différence avec la
    /// bannière, où chaque écran teste `isProEntitled` de son côté.
    @Test func aProSubscriberNeverSeesAnything() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider, isPro: true)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
        #expect(provider.loadCount == 0)
    }

    @Test func frequencyZeroCutsEverything() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider, frequency: 0)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
    }

    @Test func theSessionCapHoldsAcrossSeveralDetails() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 1)
    }

    @Test func nothingIsShownDuringAContribution() async {
        let provider = SpyInterstitialProvider()
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        coordinator.isDuringContribution = true
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
    }

    /// Un chargement raté ne présente rien, ne plante pas — et surtout ne
    /// relance pas en boucle : la règle AdMob sanctionne les requêtes
    /// excessives. Une tentative par moment éligible, pas plus.
    @Test func aFailedLoadShowsNothingAndDoesNotRetryInALoop() async {
        let provider = SpyInterstitialProvider(loadSucceeds: false)
        let coordinator = makeCoordinator(provider: provider)
        await coordinator.refreshFrequency()
        await coordinator.contentConsumed()
        await coordinator.contentConsumed()
        #expect(provider.showCount == 0)
        #expect(provider.loadCount == 2)
    }
}
```

- [ ] **Step 2: Lancer et vérifier l'échec**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialCoordinatorTests
```

Attendu : ÉCHEC de compilation, `cannot find 'InterstitialCoordinator' in scope`.

- [ ] **Step 3: Écrire le coordinateur**

Créer `NeonCompass/Core/Ads/InterstitialCoordinator.swift` :

```swift
import Foundation
import Observation

/// Le seul endroit qui décide de montrer un interstitiel.
///
/// **Pourquoi un coordinateur plutôt qu'un appel direct depuis les écrans.**
/// Aucun onglet n'a de `NavigationStack`, et les détails ne sont même pas
/// présentés de la même façon d'une feature à l'autre : `NewsDetailView` est une
/// feuille, `POIDetailView` est construit à la volée dans `MapScreen`,
/// `CheatReaderView` est un `fullScreenCover`. Il n'existe aucun point de
/// passage unique à intercepter — il faut donc en fabriquer un.
///
/// Les écrans n'ont qu'une entrée, `contentConsumed()`, et ignorent tout du
/// plafond, de l'abonnement et du réglage serveur. Ce n'est pas de l'élégance :
/// `BannerAdView` ne se protège pas elle-même et c'est chaque écran qui teste
/// `isProEntitled`. Ce motif est tolérable pour une bannière, où un oubli se
/// voit tout de suite ; il ne l'est pas pour une pleine page servie à un client
/// payant.
///
/// **L'abonnement est lu par une fermeture, pas par une référence au modèle.**
/// `WidgetSummaryCoordinator` prend `ProEntitlementModel` directement ; ici la
/// fermeture permet de vérifier les six décisions ci-contre sans construire
/// StoreKit, tout en gardant la garde à l'intérieur.
@Observable
@MainActor
final class InterstitialCoordinator {
    private let provider: any InterstitialAdProviding
    private let frequencyGate: any InterstitialFrequencyProviding
    private let isProEntitled: @MainActor () -> Bool
    private let now: @Sendable () -> Date

    private var session = InterstitialSession()
    private var frequency = SupabaseInterstitialFrequencyGate.defaultFrequency

    /// Vrai tant qu'une feuille de contribution est présentée. Le drapeau vit
    /// ici pour que `InterstitialCapPolicy` reste une fonction pure.
    var isDuringContribution = false

    init(
        provider: any InterstitialAdProviding = AdMobInterstitialProvider(),
        frequencyGate: any InterstitialFrequencyProviding = SupabaseInterstitialFrequencyGate(),
        isProEntitled: @escaping @MainActor () -> Bool,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.frequencyGate = frequencyGate
        self.isProEntitled = isProEntitled
        self.now = now
    }

    func refreshFrequency() async {
        frequency = await frequencyGate.frequency()
    }

    func didEnterBackground() {
        session.didEnterBackground(at: now())
    }

    func willEnterForeground() {
        session.willEnterForeground(at: now())
    }

    /// À appeler à la fermeture d'un écran de détail, et nulle part ailleurs.
    ///
    /// L'utilisateur a obtenu ce qu'il venait chercher et revient à une liste :
    /// c'est la pause naturelle qu'attend la règle AdMob. Jamais à l'entrée
    /// d'une tâche, jamais en pleine lecture.
    func contentConsumed() async {
        guard !isProEntitled() else { return }
        guard InterstitialCapPolicy.shouldShow(
            sessionShownCount: session.shownCount,
            isDuringContribution: isDuringContribution,
            serverFrequency: frequency
        ) else { return }

        if !provider.isReady {
            // Une seule tentative par moment éligible. Pas de reprise, pas de
            // boucle : la règle AdMob sanctionne les requêtes excessives.
            try? await provider.load()
        }
        guard provider.isReady else { return }
        if await provider.show() {
            session.recordShown()
        }
    }
}
```

- [ ] **Step 4: Lancer et vérifier le vert**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/InterstitialCoordinatorTests
```

Attendu : SUCCÈS, 6 tests.

- [ ] **Step 5: Prouver que la garde Pro sait échouer**

Remplacer temporairement `guard !isProEntitled() else { return }` par `guard true else { return }` dans `contentConsumed()`. Relancer le Step 4.

Attendu : ÉCHEC sur `aProSubscriberNeverSeesAnything`. **Rétablir** et revérifier le vert.

- [ ] **Step 6: Poser le coordinateur dans l'environnement**

Dans `NeonCompass/App/RootView.swift`, ajouter après la ligne 13 (`@State private var widgetSummaryCoordinator: WidgetSummaryCoordinator`) :

```swift
    @State private var interstitialCoordinator: InterstitialCoordinator
```

Ajouter après la ligne 19 (`@Environment(\.horizontalSizeClass) private var sizeClass`) :

```swift
    @Environment(\.scenePhase) private var scenePhase
```

Dans `init()`, ajouter après la construction de `_widgetSummaryCoordinator` :

```swift
        _interstitialCoordinator = State(initialValue: InterstitialCoordinator(
            isProEntitled: { proEntitlementModel.isProEntitled }
        ))
```

Ajouter `.environment(interstitialCoordinator)` juste après `.environment(serverFeatures)` (ligne 57).

Ajouter le rafraîchissement de la fréquence dans le `.task` existant (ligne 76-91), à la suite de `await serverFeatures.refresh()` :

```swift
            await interstitialCoordinator.refreshFrequency()
```

Ajouter, après le `.onChange(of: proEntitlementModel.isProEntitled)` existant :

```swift
        // Le plafond « un par session » ne veut rien dire sans une définition de
        // session : sur l'iPad posé à côté de la télé toute la soirée, le
        // processus ne meurt jamais. Voir `InterstitialSession`.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: interstitialCoordinator.didEnterBackground()
            case .active: interstitialCoordinator.willEnterForeground()
            default: break
            }
        }
```

- [ ] **Step 7: Poser le premier site d'appel — le fil**

Dans `NeonCompass/Features/Feed/FeedListView.swift`, ajouter après la ligne 5 :

```swift
    @Environment(InterstitialCoordinator.self) private var interstitialCoordinator
```

Remplacer la ligne 43 :

```swift
        .sheet(item: $openedItem) { item in
```

par :

```swift
        // `onDismiss` plutôt que la fermeture du bouton : il attrape aussi le
        // glissement vers le bas, qui est la façon dont la plupart des gens
        // referment une feuille.
        .sheet(item: $openedItem, onDismiss: {
            Task { await interstitialCoordinator.contentConsumed() }
        }) { item in
```

- [ ] **Step 8: Poser le second site d'appel — le lecteur de codes**

Dans `NeonCompass/Features/Cheats/CheatsScreen.swift`, ajouter après la ligne 6 :

```swift
    @Environment(InterstitialCoordinator.self) private var interstitialCoordinator
```

Remplacer la ligne 50 :

```swift
        .fullScreenCover(item: $readerCheat) { cheat in
```

par :

```swift
        .fullScreenCover(item: $readerCheat, onDismiss: {
            Task { await interstitialCoordinator.contentConsumed() }
        }) { cheat in
```

**La carte n'en reçoit pas.** C'était le troisième site évident, et il est écarté : c'est là que le geste s'enchaîne — on ouvre une fiche POI, on la referme, on en ouvre une autre. Une pleine page au milieu de cette boucle est l'interruption la plus coûteuse que l'app puisse produire, sur l'écran qui justifie son existence.

- [ ] **Step 9: Build, suite complète, commit**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
git status --short
git add NeonCompass/Core/Ads/InterstitialCoordinator.swift NeonCompassTests/Ads/InterstitialCoordinatorTests.swift \
        NeonCompass/App/RootView.swift NeonCompass/Features/Feed/FeedListView.swift \
        NeonCompass/Features/Cheats/CheatsScreen.swift
git commit -m "feat(pub): l'interstitiel écrit depuis juillet est enfin déclenché"
```

---

### Task 5 : l'ATT après le RGPD, et à la deuxième session

**Files:**
- Create: `NeonCompass/Features/Onboarding/TrackingExplainerView.swift`
- Test: `NeonCompassTests/Onboarding/OnboardingModelTests.swift`
- Modify: `NeonCompass/Features/Onboarding/OnboardingModel.swift`
- Modify: `NeonCompass/App/RootView.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ConsentProviding.requestConsent() async throws -> Bool` (existant).
- Produces: sur `OnboardingModel` — `var needsDisclaimer: Bool`, `var needsConsentPrompt: Bool { get }`, `var needsTrackingExplainer: Bool { get }`, `func acceptDisclaimer()`, `func requestConsent() async`, `func requestTrackingAuthorization() async`, `func deferTrackingExplainer()`, `func registerLaunch()`. **`needsATTPrompt` disparaît.**

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Onboarding/OnboardingModelTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

private struct StubConsent: ConsentProviding {
    var granted: Bool
    var throwsOnRequest = false

    func requestConsent() async throws -> Bool {
        if throwsOnRequest { throw URLError(.timedOut) }
        return granted
    }
}

@MainActor
struct OnboardingModelTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "OnboardingModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(
        defaults: UserDefaults,
        granted: Bool = true,
        throwsOnRequest: Bool = false
    ) -> OnboardingModel {
        OnboardingModel(
            defaults: defaults,
            consentProvider: StubConsent(granted: granted, throwsOnRequest: throwsOnRequest)
        )
    }

    /// L'explication ATT ne doit pas apparaître au premier lancement : c'est le
    /// pire moment possible pour un opt-in, avant que l'utilisateur ait vu la
    /// moindre valeur.
    @Test func theExplainerIsNotOfferedOnTheFirstLaunch() async {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults)
        model.acceptDisclaimer()
        model.registerLaunch()
        await model.requestConsent()
        #expect(!model.needsTrackingExplainer)
    }

    @Test func theExplainerIsOfferedOnTheSecondLaunch() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        #expect(second.needsTrackingExplainer)
    }

    /// Demander l'IDFA à quelqu'un qui vient de refuser le RGPD, c'est brûler
    /// l'unique demande que le système autorise par installation.
    @Test func aRefusedConsentNeverLeadsToTheATTPrompt() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults, granted: false)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults, granted: false)
        second.registerLaunch()
        #expect(!second.needsTrackingExplainer)
    }

    /// Un UMP en échec est traité comme une absence de consentement — et il ne
    /// bloque pas l'app pour autant.
    @Test func aFailedConsentFlowResolvesTheGateWithoutGranting() async {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults, throwsOnRequest: true)
        model.acceptDisclaimer()
        model.registerLaunch()
        await model.requestConsent()
        #expect(!model.needsConsentPrompt)
    }

    @Test func decliningTheExplainerHidesItForThisSession() async {
        let defaults = freshDefaults()
        let first = makeModel(defaults: defaults)
        first.acceptDisclaimer()
        first.registerLaunch()
        await first.requestConsent()

        let second = makeModel(defaults: defaults)
        second.registerLaunch()
        second.deferTrackingExplainer()
        #expect(!second.needsTrackingExplainer)
    }

    /// Le compteur ne bouge qu'une fois par processus, quel que soit le nombre
    /// de fois que SwiftUI reconstruit la vue qui l'appelle.
    @Test func launchesAreCountedOncePerProcess() async {
        let defaults = freshDefaults()
        let model = makeModel(defaults: defaults)
        model.registerLaunch()
        model.registerLaunch()
        model.registerLaunch()
        #expect(defaults.integer(forKey: "launchCount") == 1)
    }
}
```

- [ ] **Step 2: Lancer et vérifier l'échec**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnboardingModelTests
```

Attendu : ÉCHEC de compilation, `value of type 'OnboardingModel' has no member 'needsTrackingExplainer'`.

- [ ] **Step 3: Réécrire `OnboardingModel`**

Remplacer intégralement `NeonCompass/Features/Onboarding/OnboardingModel.swift` :

```swift
import AppTrackingTransparency
import Foundation
import Observation

/// Les portes d'entrée de l'app, dans l'ordre où Google les documente.
///
/// **Cet ordre était l'inverse.** L'implémentation d'origine demandait l'ATT
/// AVANT le formulaire RGPD, au premier lancement. Deux conséquences : on
/// brûlait l'unique demande ATT autorisée par installation sur des utilisateurs
/// qui refusaient le consentement trois secondes plus tard, et on la posait au
/// pire moment possible pour un opt-in — avant que l'utilisateur ait vu la
/// moindre valeur.
///
/// L'ordre retenu : disclaimer, puis UMP, puis — à la DEUXIÈME session
/// seulement, et uniquement si le consentement a été accordé — l'explication
/// maison puis la boîte système.
@Observable
@MainActor
final class OnboardingModel {
    private static let disclaimerKey = "hasAcceptedDisclaimer"
    private static let attPromptShownKey = "hasShownATTPrompt"
    private static let consentResolvedKey = "hasResolvedAdConsent"
    private static let consentGrantedKey = "adConsentGranted"
    private static let launchCountKey = "launchCount"

    private let defaults: UserDefaults
    private let consentProvider: ConsentProviding

    var needsDisclaimer: Bool
    private(set) var needsConsentPrompt: Bool
    private(set) var hasShownATTPrompt: Bool
    /// Persisté : à la deuxième session le formulaire n'est plus présenté, mais
    /// on doit encore savoir ce qu'il avait répondu.
    private(set) var consentGranted: Bool
    private(set) var launchCount: Int

    private var hasRegisteredLaunch = false
    private var isExplainerDeferred = false

    init(defaults: UserDefaults = .standard, consentProvider: ConsentProviding = UMPConsentProvider()) {
        self.defaults = defaults
        self.consentProvider = consentProvider
        needsDisclaimer = !defaults.bool(forKey: Self.disclaimerKey)
        needsConsentPrompt = !defaults.bool(forKey: Self.consentResolvedKey)
        hasShownATTPrompt = defaults.bool(forKey: Self.attPromptShownKey)
        consentGranted = defaults.bool(forKey: Self.consentGrantedKey)
        launchCount = defaults.integer(forKey: Self.launchCountKey)
    }

    /// Compte une session, une seule fois par processus.
    ///
    /// SwiftUI peut réévaluer l'expression initiale d'un `@State` et reconstruit
    /// `RootView` souvent : compter dans `init` gonflerait le total et
    /// avancerait la demande ATT. Le garde-fou est ici, pas chez l'appelant.
    func registerLaunch() {
        guard !hasRegisteredLaunch else { return }
        hasRegisteredLaunch = true
        let next = defaults.integer(forKey: Self.launchCountKey) + 1
        defaults.set(next, forKey: Self.launchCountKey)
        launchCount = next
    }

    func acceptDisclaimer() {
        defaults.set(true, forKey: Self.disclaimerKey)
        needsDisclaimer = false
    }

    /// Le booléen rendu par UMP n'est plus jeté.
    ///
    /// `ConsentProviding.requestConsent()` répond « peut-on demander des
    /// pubs ». L'implémentation d'origine l'écrasait avec `_ = try? await`, et
    /// c'est exactement le signal qui permet de ne pas présenter l'ATT après un
    /// refus RGPD. Un échec de lecture vaut un refus : on résout la porte pour
    /// ne pas bloquer l'app, sans accorder quoi que ce soit.
    func requestConsent() async {
        let granted = (try? await consentProvider.requestConsent()) ?? false
        defaults.set(granted, forKey: Self.consentGrantedKey)
        defaults.set(true, forKey: Self.consentResolvedKey)
        consentGranted = granted
        needsConsentPrompt = false
    }

    /// L'explication maison, et donc la boîte système, ne sont proposées qu'à
    /// partir de la deuxième session — quelqu'un qui revient a déjà jugé l'app
    /// utile et accepte bien plus volontiers.
    var needsTrackingExplainer: Bool {
        !hasShownATTPrompt
            && consentGranted
            && launchCount >= 2
            && !isExplainerDeferred
            && !needsDisclaimer
            && !needsConsentPrompt
    }

    /// « Plus tard » : on ne présente rien cette fois, et on redemandera au
    /// prochain lancement. Rien n'est persisté — refuser l'explication n'est pas
    /// refuser le suivi, et n'a donc pas à être définitif.
    func deferTrackingExplainer() {
        isExplainerDeferred = true
    }

    /// La boîte système d'Apple ne s'affiche qu'une fois par installation : un
    /// second appel rend le statut mémorisé, sans dialogue. Le drapeau ci-dessous
    /// sert à ne pas re-proposer NOTRE écran, pas à contourner ce comportement.
    ///
    /// - Important: `requestTrackingAuthorization` échoue en silence si l'app
    ///   n'est pas active. L'appelant doit donc être un moment de premier plan —
    ///   ici, le bouton d'une feuille présentée.
    func requestTrackingAuthorization() async {
        _ = await ATTrackingManager.requestTrackingAuthorization()
        defaults.set(true, forKey: Self.attPromptShownKey)
        hasShownATTPrompt = true
    }
}
```

- [ ] **Step 4: Écrire l'écran d'explication**

Créer `NeonCompass/Features/Onboarding/TrackingExplainerView.swift` :

```swift
import SwiftUI

/// L'explication qui précède la boîte système d'Apple.
///
/// **Pourquoi un écran maison plutôt que le message ATT hébergé par Google.**
/// Le message de la console Privacy & messaging éviterait ce fichier et serait
/// modifiable sans mise à jour — mais il s'affiche pendant le flux de
/// consentement, au premier lancement. Les deux options s'excluent, et celle qui
/// porte le gain d'opt-in est celle qui attend la deuxième session.
///
/// Le texte reste neutre et ne promet rien : une pré-demande qui incite ou qui
/// laisse croire que la boîte système est autre chose est un motif de rejet.
struct TrackingExplainerView: View {
    let onContinue: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 56))
                .foregroundStyle(NCColor.neonCyan)
                .accessibilityHidden(true)

            Text("att.explainer.title")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("att.explainer.body")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("att.explainer.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("att.explainer.later", action: onLater)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 5: Ajouter les chaînes au String Catalog**

Ouvrir `NeonCompass/Resources/Localizable.xcstrings` et ajouter quatre clés, avec les cinq langues (`en` base, plus `fr`, `es`, `it`, `de`) :

| Clé | en | fr |
|---|---|---|
| `att.explainer.title` | Ads keep this app free | La publicité garde cette app gratuite |
| `att.explainer.body` | Apple will now ask whether we may use your device identifier. Allowing it lets us show ads that are worth more, so we can keep everything free. Declining changes nothing to what the app does. | Apple va vous demander si nous pouvons utiliser l'identifiant de votre appareil. L'autoriser nous permet d'afficher des publicités mieux rémunérées, et donc de tout garder gratuit. Refuser ne change rien à ce que fait l'app. |
| `att.explainer.continue` | Continue | Continuer |
| `att.explainer.later` | Not now | Plus tard |

Traduire `es`, `it`, `de` sur le même sens. Ne promettre aucune contrepartie et ne pas suggérer que refuser dégrade l'app — ce serait un motif de rejet.

- [ ] **Step 6: Recâbler `RootView`**

Dans `NeonCompass/App/RootView.swift`, remplacer le bloc `Group` du `body` (lignes 35-49) :

```swift
        Group {
            if onboarding.needsDisclaimer {
                DisclaimerView { onboarding.acceptDisclaimer() }
            } else if onboarding.needsConsentPrompt {
                ProgressView()
                    .task { await onboarding.requestConsent() }
            } else if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
```

Remplacer le `.task(id:)` du démarrage du SDK (lignes 66-75) :

```swift
        // Le SDK démarre dès que le consentement UMP est résolu, SANS attendre
        // l'ATT : sans autorisation il n'utilise simplement pas l'IDFA et sert
        // du contextuel. Attendre l'ATT — qui n'arrive qu'à la deuxième session —
        // repousserait toute la publicité, l'inverse du but.
        .task(id: onboarding.needsConsentPrompt) {
            guard !onboarding.needsDisclaimer, !onboarding.needsConsentPrompt else { return }
            await MobileAds.shared.start()
        }
```

Ajouter `onboarding.registerLaunch()` en première ligne du `.task` de démarrage (ligne 76), avant `await ContentSourceConfigurator.configureFromAppConfig()`.

Ajouter l'état et la feuille. Après `@State private var builtTabs: Set<AppTab> = []` :

```swift
    @State private var showsTrackingExplainer = false
```

Et à la suite du `.onChange(of: scenePhase)` ajouté en Task 4 :

```swift
        // Une feuille et non une porte : l'app est utilisable pendant ce temps,
        // et `requestTrackingAuthorization` a besoin que l'app soit active — ce
        // qu'un écran de démarrage ne garantit pas.
        .onChange(of: onboarding.needsTrackingExplainer, initial: true) { _, needs in
            showsTrackingExplainer = needs
        }
        .sheet(isPresented: $showsTrackingExplainer) {
            TrackingExplainerView(
                onContinue: {
                    showsTrackingExplainer = false
                    Task { await onboarding.requestTrackingAuthorization() }
                },
                onLater: {
                    showsTrackingExplainer = false
                    onboarding.deferTrackingExplainer()
                }
            )
            .interactiveDismissDisabled()
        }
```

- [ ] **Step 7: Lancer les tests et vérifier le vert**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/OnboardingModelTests
```

Attendu : SUCCÈS, 6 tests.

- [ ] **Step 8: Prouver que la garde du refus RGPD sait échouer**

Remplacer temporairement `&& consentGranted` par `&& true` dans `needsTrackingExplainer`. Relancer le Step 7.

Attendu : ÉCHEC sur `aRefusedConsentNeverLeadsToTheATTPrompt`. **Rétablir** et revérifier le vert.

- [ ] **Step 9: Build, suite complète, commit**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
git status --short
```

`Localizable.xcstrings` doit apparaître modifié — c'est voulu ici, on y a ajouté quatre clés. Vérifier que le diff ne contient QUE ces quatre clés et pas de variantes à suffixe `%@` ajoutées par l'extraction automatique ; le cas échéant, les retirer.

```sh
git add NeonCompass/Features/Onboarding/OnboardingModel.swift \
        NeonCompass/Features/Onboarding/TrackingExplainerView.swift \
        NeonCompassTests/Onboarding/OnboardingModelTests.swift \
        NeonCompass/App/RootView.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(pub): l'ATT arrive après le RGPD, et à la deuxième session"
```

---

## Auto-relecture

**Couverture de la spec.** Chantier 1 → Task 1 (`AdUnits`, `#if DEBUG`, `$(GAD_APP_ID)`, test de garde). Chantier 2 → Tasks 2, 3, 4 (`InterstitialSession`, `serverFrequency` + `app_config`, `InterstitialCoordinator`, deux sites d'appel, carte exclue, garde Pro interne). Chantier 3 → Task 5 (ordre inversé, découplage du démarrage du SDK, deuxième session, écran maison, garde du refus RGPD). Les quatre suites de tests annoncées par la spec existent : `AdUnitsTests`, `InterstitialSessionTests`, `InterstitialCoordinatorTests`, `OnboardingModelTests` — plus `InterstitialFrequencyGateTests`, qui n'était pas nommée mais qu'exige le défaut ouvert.

**Non couvert, et c'est volontaire :** `app-ads.txt` et le provisioning AdMob sont des tâches d'ops sans code, listées dans la spec §« Ce qui dépend de l'humain ». Le `TODO(ops)` d'`AdUnits` et celui de `project.yml` sont les points de reprise.

**Cohérence des types.** `serverFrequency` est renommé en Task 3 et consommé sous ce nom en Task 4. `InterstitialSession` expose `shownCount`, lu par le coordinateur. `needsATTPrompt` disparaît en Task 5 ; sa seule lecture hors du modèle était le `.task(id:)` de `RootView`, réécrit dans le même Step. `InterstitialFrequencyProviding` est produit en Task 3 et injecté en Task 4 sous le même nom.

**Un point d'attention pour l'exécutant.** Task 4 Step 6 et Task 5 Step 6 modifient tous deux `RootView.swift`. Exécuter les tâches dans l'ordre : le `.onChange(of: scenePhase)` posé en Task 4 est le point d'ancrage cité par Task 5.
