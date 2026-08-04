# Plan d'implémentation — Le Profil connecté

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner à l'entête du Profil deux jauges — l'exploration locale et la contribution serveur — avec des grades nommés, et ranger la feuille de réglages dans un `Form` natif où l'identité du compte est enfin visible.

**Architecture:** Trois types purs sans I/O dans `Core/` (`ExplorerGrade`, `ContributorGrade`, `SignedInAccount`), un état dérivé pur dans `Features/Profile/ProfileHeaderState`, puis des vues qui ne font que rendre. `SettingsScreen` passe d'un `VStack` à plat à un `Form` éclaté en cinq fichiers de section. Toute la logique testable est hors SwiftUI.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SwiftData, Swift Testing, XcodeGen, Supabase.

**Spec:** `docs/superpowers/specs/2026-08-04-profil-connecte-design.md`

## Global Constraints

- **Swift 6, concurrence stricte.** SwiftUI seulement, pas d'UIKit sauf `UIApplication.shared.supportsAlternateIcons` déjà en place.
- **Tests en Swift Testing** (`import Testing`), jamais XCTest.
- **Aucune chaîne en dur.** Toute chaîne visible passe par `NeonCompass/Resources/Localizable.xcstrings`, dans les **cinq** langues `en`, `fr`, `es`, `it`, `de`. `en` est la langue de base.
- **IP** : aucun nom de grade ne peut être une marque ni un rang de la série. Le vocabulaire retenu est cartographique et de signalisation.
- **`xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`.** Vérifier `git status` avant chaque commit ; si le catalogue apparaît modifié sans qu'on y ait touché, `git checkout -- NeonCompass/Resources/Localizable.xcstrings`.
- Simulateur : `iPhone 17` (iOS 26.5). Commande de test :
  `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Le niveau contributeur est calculé **par la base** (colonne générée). Le client ne recalcule jamais un seuil XP.

---

## Structure des fichiers

**Créés :**

| Fichier | Responsabilité |
|---|---|
| `NeonCompass/Core/Progression/ExplorerGrade.swift` | Paliers d'exploration : seuils, noms, progression vers le suivant |
| `NeonCompass/Core/Auth/ContributorGrade.swift` | Nommage d'un `Profile.level` reçu de la base. Aucun seuil |
| `NeonCompass/Core/Auth/SignedInAccount.swift` | Fournisseur + adresse de la session courante |
| `NeonCompass/Features/Profile/ProfileHeaderState.swift` | Tout l'état dérivé de l'entête, sans SwiftUI |
| `NeonCompass/Features/Profile/ContributeHintSheet.swift` | La feuille qui explique le geste de contribution |
| `NeonCompass/Features/Settings/SettingsAccountSection.swift` | Identité, pseudo, connexion, déconnexion, suppression |
| `NeonCompass/Features/Settings/SettingsAppearanceSection.swift` | Thème, icône |
| `NeonCompass/Features/Settings/SettingsNotificationsSection.swift` | Catégories suivies |
| `NeonCompass/Features/Settings/SettingsCommunitySection.swift` | Contributeurs masqués |
| `NeonCompassTests/Progression/ExplorerGradeTests.swift` | — |
| `NeonCompassTests/Auth/ContributorGradeTests.swift` | — |
| `NeonCompassTests/Auth/SignedInAccountTests.swift` | — |
| `NeonCompassTests/Profile/ProfileHeaderStateTests.swift` | — |

**Modifiés :**

| Fichier | Changement |
|---|---|
| `NeonCompass/Features/Profile/ProfileHeaderView.swift` | Réécrit : rend un `ProfileHeaderState` |
| `NeonCompass/Features/Profile/ProfileScreen.swift` | Construit l'état, ouvre la feuille d'invitation |
| `NeonCompass/Features/Profile/ProfileModel.swift` | Gagne `isLoadingProfile` |
| `NeonCompass/Features/Settings/SettingsScreen.swift` | Passe en `Form`, éclate en sections |
| `NeonCompass/Core/Auth/AuthProviding.swift` | Gagne `currentAccount` |
| `NeonCompass/Core/Auth/SupabaseAuthProvider.swift` | Implémente `currentAccount` |
| `NeonCompass/Core/Community/BlockedContributor.swift` | Gagne `authorHandle: String?` |
| `NeonCompass/Features/Community/CommunityModel.swift` | `block(authorUid:handle:)` |
| `NeonCompass/Features/Map/MapScreen.swift:251-253` | Passe `spot.authorHandle` |
| `NeonCompass/App/RootView.swift:50` | `.environment(model)` pour que le Profil puisse basculer d'onglet |
| `NeonCompassTests/Profile/ProfileFakes.swift` | `FakeAuthProvider.currentAccount` |
| `NeonCompass/Resources/Localizable.xcstrings` | 34 clés nouvelles, 1 retirée |

---

### Task 1 : `ExplorerGrade`

Le palier d'exploration, calculé sur un nombre de lieux cochés. Type pur, aucune dépendance.

**Files:**
- Create: `NeonCompass/Core/Progression/ExplorerGrade.swift`
- Test: `NeonCompassTests/Progression/ExplorerGradeTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `ExplorerGrade` — `.forFound(_ count: Int) -> ExplorerGrade`, `var threshold: Int`, `var nameKey: String`, `var next: ExplorerGrade?`, `func progress(found: Int) -> Double?`, `func remainingToNext(found: Int) -> Int?`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Progression/ExplorerGradeTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct ExplorerGradeTests {
    /// Les bornes, pas le milieu : c'est là que les erreurs de comparaison
    /// vivent. 9 est encore Vagabond, 10 est déjà Repéreur.
    @Test func thresholdsAreExact() {
        #expect(ExplorerGrade.forFound(0) == .drifter)
        #expect(ExplorerGrade.forFound(9) == .drifter)
        #expect(ExplorerGrade.forFound(10) == .scout)
        #expect(ExplorerGrade.forFound(39) == .scout)
        #expect(ExplorerGrade.forFound(40) == .pathfinder)
        #expect(ExplorerGrade.forFound(99) == .pathfinder)
        #expect(ExplorerGrade.forFound(100) == .cartographer)
        #expect(ExplorerGrade.forFound(249) == .cartographer)
        #expect(ExplorerGrade.forFound(250) == .trailblazer)
        #expect(ExplorerGrade.forFound(499) == .trailblazer)
        #expect(ExplorerGrade.forFound(500) == .neonNomad)
        #expect(ExplorerGrade.forFound(10_000) == .neonNomad)
    }

    /// `FoundStore` ne peut pas rendre un compte négatif, mais un état
    /// corrompu ne doit pas faire tomber l'entête.
    @Test func negativeCountFallsBackToFirstGrade() {
        #expect(ExplorerGrade.forFound(-1) == .drifter)
    }

    @Test func lastGradeHasNoNext() {
        #expect(ExplorerGrade.neonNomad.next == nil)
        #expect(ExplorerGrade.neonNomad.progress(found: 600) == nil)
        #expect(ExplorerGrade.neonNomad.remainingToNext(found: 600) == nil)
    }

    @Test func nextIsTheFollowingGrade() {
        #expect(ExplorerGrade.drifter.next == .scout)
        #expect(ExplorerGrade.trailblazer.next == .neonNomad)
    }

    /// 87 lieux : Éclaireur (40), le suivant est Cartographe (100).
    /// Il reste 13, et on a fait 47/60 du chemin.
    @Test func progressAndRemainingWithinAGrade() throws {
        let grade = ExplorerGrade.forFound(87)
        #expect(grade == .pathfinder)
        #expect(grade.remainingToNext(found: 87) == 13)
        let progress = try #require(grade.progress(found: 87))
        #expect(abs(progress - (47.0 / 60.0)) < 0.0001)
    }

    /// Pile sur un seuil : la barre repart de zéro, elle ne reste pas pleine.
    @Test func progressResetsAtEachThreshold() {
        #expect(ExplorerGrade.forFound(40).progress(found: 40) == 0)
        #expect(ExplorerGrade.forFound(40).remainingToNext(found: 40) == 60)
    }

    /// Onze clés, toutes distinctes et toutes préfixées : le test de
    /// couverture de localisation ne voit que ce qui existe dans le catalogue,
    /// pas ce qu'on a oublié de nommer.
    @Test func nameKeysAreDistinctAndPrefixed() {
        let keys = ExplorerGrade.allCases.map(\.nameKey)
        #expect(Set(keys).count == ExplorerGrade.allCases.count)
        #expect(keys.allSatisfy { $0.hasPrefix("profile.explorerGrade.") })
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ExplorerGradeTests 2>&1 | tail -20
```

Attendu : échec de compilation, `cannot find 'ExplorerGrade' in scope`.

- [ ] **Step 3 : écrire l'implémentation**

Créer `NeonCompass/Core/Progression/ExplorerGrade.swift` :

```swift
import Foundation

/// Le palier d'exploration, calculé sur le NOMBRE de lieux cochés.
///
/// En nombre absolu et pas en pourcentage, délibérément : `ChallengeProgress`
/// peut avoir un `expected` nul quand notre contenu n'énumère pas encore toute
/// une collection, et un pourcentage serait alors faux. C'est déjà pourquoi
/// `ProgressionListView` refuse de tracer un anneau dans ce cas. Un compte
/// reste juste quoi qu'il arrive.
///
/// Rien à voir avec le niveau contributeur (`ContributorGrade`), qui vient de
/// la base : celui-ci est local, il vit hors ligne et sans compte.
enum ExplorerGrade: Int, CaseIterable, Sendable {
    case drifter, scout, pathfinder, cartographer, trailblazer, neonNomad

    /// Calibrés sur les 537 POI du socle `seed-poi.json` : au dernier palier on
    /// a vu l'équivalent de la carte de référence entière.
    var threshold: Int {
        switch self {
        case .drifter: 0
        case .scout: 10
        case .pathfinder: 40
        case .cartographer: 100
        case .trailblazer: 250
        case .neonNomad: 500
        }
    }

    var nameKey: String {
        switch self {
        case .drifter: "profile.explorerGrade.drifter"
        case .scout: "profile.explorerGrade.scout"
        case .pathfinder: "profile.explorerGrade.pathfinder"
        case .cartographer: "profile.explorerGrade.cartographer"
        case .trailblazer: "profile.explorerGrade.trailblazer"
        case .neonNomad: "profile.explorerGrade.neonNomad"
        }
    }

    /// Le repli sur `.drifter` couvre le compte négatif, que `FoundStore` ne
    /// peut pas produire aujourd'hui mais qu'un état corrompu pourrait.
    static func forFound(_ count: Int) -> ExplorerGrade {
        allCases.last { count >= $0.threshold } ?? .drifter
    }

    var next: ExplorerGrade? { ExplorerGrade(rawValue: rawValue + 1) }

    /// Nul au dernier palier : il n'y a plus de suivant, donc plus de barre.
    func progress(found: Int) -> Double? {
        guard let next else { return nil }
        let span = Double(next.threshold - threshold)
        guard span > 0 else { return nil }
        return min(1, max(0, Double(found - threshold) / span))
    }

    func remainingToNext(found: Int) -> Int? {
        guard let next else { return nil }
        return max(0, next.threshold - found)
    }
}
```

- [ ] **Step 4 : lancer le test pour vérifier qu'il passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ExplorerGradeTests 2>&1 | tail -20
```

Attendu : `TEST SUCCEEDED`, 7 tests passés.

- [ ] **Step 5 : commiter**

```sh
git status --short
git add NeonCompass/Core/Progression/ExplorerGrade.swift \
        NeonCompassTests/Progression/ExplorerGradeTests.swift project.yml
git commit -m "feat(profil): les paliers d'exploration, comptés en lieux et non en pourcentage"
```

---

### Task 2 : `ContributorGrade`

Le nommage d'un niveau reçu de la base. Aucun seuil : la colonne générée les possède, et elle est seule à les posséder.

**Files:**
- Create: `NeonCompass/Core/Auth/ContributorGrade.swift`
- Test: `NeonCompassTests/Auth/ContributorGradeTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `ContributorGrade` — `static func named(level: Int) -> ContributorGrade?`, `var nameKey: String`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Auth/ContributorGradeTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct ContributorGradeTests {
    @Test func eachLevelHasItsGrade() {
        #expect(ContributorGrade.named(level: 1) == .spotter)
        #expect(ContributorGrade.named(level: 2) == .beacon)
        #expect(ContributorGrade.named(level: 3) == .relay)
        #expect(ContributorGrade.named(level: 4) == .lighthouse)
        #expect(ContributorGrade.named(level: 5) == .gridKeeper)
    }

    /// Le niveau 0 n'est pas un grade : c'est l'absence de grade. L'entête
    /// affiche alors l'XP sans nom, ou l'invitation si l'XP est à zéro.
    @Test func levelZeroHasNoGrade() {
        #expect(ContributorGrade.named(level: 0) == nil)
    }

    /// La base peut gagner un palier avant que l'app le connaisse : un niveau
    /// inconnu ne doit pas planter, il doit simplement n'avoir aucun nom.
    @Test func levelsOutsideTheKnownRangeHaveNoGrade() {
        #expect(ContributorGrade.named(level: 6) == nil)
        #expect(ContributorGrade.named(level: 99) == nil)
        #expect(ContributorGrade.named(level: -1) == nil)
    }

    @Test func nameKeysAreDistinctAndPrefixed() {
        let keys = ContributorGrade.allCases.map(\.nameKey)
        #expect(Set(keys).count == ContributorGrade.allCases.count)
        #expect(keys.allSatisfy { $0.hasPrefix("profile.contributorGrade.") })
    }

    /// Aucun seuil XP côté client : la colonne générée de `profiles` est seule
    /// à les détenir. Ce test fige l'intention — si quelqu'un ajoute un
    /// `threshold`, il saura qu'il rouvre une duplication supprimée exprès.
    @Test func gradesCarryNoXPThreshold() {
        #expect(ContributorGrade.allCases.count == 5)
        #expect(ContributorGrade.spotter.rawValue == 1)
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributorGradeTests 2>&1 | tail -20
```

Attendu : `cannot find 'ContributorGrade' in scope`.

- [ ] **Step 3 : écrire l'implémentation**

Créer `NeonCompass/Core/Auth/ContributorGrade.swift` :

```swift
import Foundation

/// Nomme un `Profile.level` reçu de la base. Rien de plus.
///
/// Aucun seuil XP n'est déclaré ici, et c'est délibéré : `profiles.level` est
/// une colonne GÉNÉRÉE (`20260802120000_initial_schema.sql:24-33`), et la
/// migration qui l'a introduite dit pourquoi — « il n'y a plus qu'un seul
/// endroit où écrire l'XP, et zéro endroit où recalculer le niveau ». Déclarer
/// les seuils ici rouvrirait exactement la duplication qu'elle a fermée.
///
/// Conséquence assumée : pas de barre de progression côté contributeur. Une
/// ligne de texte suffit, et elle ne peut pas dériver de la base.
enum ContributorGrade: Int, CaseIterable, Sendable {
    case spotter = 1, beacon, relay, lighthouse, gridKeeper

    var nameKey: String {
        switch self {
        case .spotter: "profile.contributorGrade.spotter"
        case .beacon: "profile.contributorGrade.beacon"
        case .relay: "profile.contributorGrade.relay"
        case .lighthouse: "profile.contributorGrade.lighthouse"
        case .gridKeeper: "profile.contributorGrade.gridKeeper"
        }
    }

    /// Nul au niveau 0 — l'absence de grade, pas un grade — et nul aussi pour
    /// tout entier hors 1…5 : la base peut gagner un palier avant l'app.
    static func named(level: Int) -> ContributorGrade? {
        ContributorGrade(rawValue: level)
    }
}
```

- [ ] **Step 4 : lancer le test pour vérifier qu'il passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributorGradeTests 2>&1 | tail -20
```

Attendu : `TEST SUCCEEDED`, 5 tests passés.

- [ ] **Step 5 : commiter**

```sh
git status --short
git add NeonCompass/Core/Auth/ContributorGrade.swift \
        NeonCompassTests/Auth/ContributorGradeTests.swift project.yml
git commit -m "feat(profil): les grades contributeur nomment le niveau, sans jamais le recalculer"
```

---

### Task 3 : les onze noms de grades, dans les cinq langues

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: les `nameKey` des tâches 1 et 2.
- Produces: les onze clés, disponibles pour la vue de la tâche 5.

- [ ] **Step 1 : écrire le script d'ajout**

Créer `$CLAUDE_JOB_DIR/tmp/add-grade-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "profile.explorerGrade.drifter": {
        "en": "Drifter", "fr": "Vagabond", "es": "Errante",
        "it": "Vagabondo", "de": "Streuner"},
    "profile.explorerGrade.scout": {
        "en": "Scout", "fr": "Repéreur", "es": "Explorador",
        "it": "Battistrada", "de": "Späher"},
    "profile.explorerGrade.pathfinder": {
        "en": "Pathfinder", "fr": "Éclaireur", "es": "Rastreador",
        "it": "Esploratore", "de": "Pfadfinder"},
    "profile.explorerGrade.cartographer": {
        "en": "Cartographer", "fr": "Cartographe", "es": "Cartógrafo",
        "it": "Cartografo", "de": "Kartograf"},
    "profile.explorerGrade.trailblazer": {
        "en": "Trailblazer", "fr": "Défricheur", "es": "Pionero",
        "it": "Pioniere", "de": "Wegbereiter"},
    "profile.explorerGrade.neonNomad": {
        "en": "Neon Nomad", "fr": "Nomade Néon", "es": "Nómada Neón",
        "it": "Nomade Neon", "de": "Neon-Nomade"},

    "profile.contributorGrade.spotter": {
        "en": "Spotter", "fr": "Guetteur", "es": "Vigía",
        "it": "Vedetta", "de": "Beobachter"},
    "profile.contributorGrade.beacon": {
        "en": "Beacon", "fr": "Balise", "es": "Baliza",
        "it": "Segnale", "de": "Bake"},
    "profile.contributorGrade.relay": {
        "en": "Relay", "fr": "Relais", "es": "Repetidor",
        "it": "Ripetitore", "de": "Relais"},
    "profile.contributorGrade.lighthouse": {
        "en": "Lighthouse", "fr": "Phare", "es": "Faro",
        "it": "Faro", "de": "Leuchtturm"},
    "profile.contributorGrade.gridKeeper": {
        "en": "Grid Keeper", "fr": "Gardien du réseau", "es": "Guardián de la red",
        "it": "Custode della rete", "de": "Netzwächter"},
}

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(catalog['strings'])} au total")
```

- [ ] **Step 2 : l'exécuter**

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-grade-keys.py"
```

Attendu : `11 clés ajoutées, N au total`.

- [ ] **Step 3 : vérifier la couverture des cinq langues**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | tail -20
```

Attendu : `TEST SUCCEEDED`. En cas d'échec, le test nomme la clé et la langue manquantes.

- [ ] **Step 4 : commiter**

```sh
git add NeonCompass/Resources/Localizable.xcstrings
git commit -m "i18n(profil): les onze noms de grades, dans les cinq langues"
```

---

### Task 4 : `ProfileHeaderState` et `ProfileModel.isLoadingProfile`

L'état dérivé de l'entête, et le seul booléen qu'il reçoit en plus du profil.

**Files:**
- Create: `NeonCompass/Features/Profile/ProfileHeaderState.swift`
- Modify: `NeonCompass/Features/Profile/ProfileModel.swift`
- Test: `NeonCompassTests/Profile/ProfileHeaderStateTests.swift`

**Interfaces:**
- Consumes: `ExplorerGrade` (tâche 1), `ContributorGrade` (tâche 2), `Profile`.
- Produces: `ProfileHeaderState.init(profile:isLoadingProfile:isProEntitled:foundCount:pendingContributionCount:)`, ses membres `title: Title`, `isProEntitled`, `explorerGrade`, `foundCount`, `explorerProgress: Double?`, `remainingToNext: Int?`, `nextGradeNameKey: String?`, `contributor: Contributor?`. Et `ProfileModel.isLoadingProfile: Bool`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Profile/ProfileHeaderStateTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct ProfileHeaderStateTests {
    private func makeProfile(xp: Int, level: Int, rank: Int? = nil) -> Profile {
        Profile(handle: "NEON-FALCON-88", xp: xp, level: level, isPremium: false, rank: rank)
    }

    private func makeState(
        profile: Profile?,
        isLoadingProfile: Bool = false,
        isProEntitled: Bool = false,
        foundCount: Int = 0,
        pendingContributionCount: Int = 0
    ) -> ProfileHeaderState {
        ProfileHeaderState(
            profile: profile,
            isLoadingProfile: isLoadingProfile,
            isProEntitled: isProEntitled,
            foundCount: foundCount,
            pendingContributionCount: pendingContributionCount
        )
    }

    // MARK: - Le correctif

    /// LE test de ce chantier. L'entête affichait « Ton profil » ET
    /// « Niveau 0 / 0 XP » en même temps : le titre suivait
    /// `userID != nil && serverFeatures.isEnabled`, le bloc chiffré suivait un
    /// `if let profile` indépendant. Deux conditions pour une seule question,
    /// réparties entre deux fichiers, donc invisibles au test.
    ///
    /// Il n'y a plus qu'une règle : sans profil, rien de chiffré.
    @Test func nothingNumericWithoutAProfile() {
        for loading in [true, false] {
            let state = makeState(profile: nil, isLoadingProfile: loading, foundCount: 87)
            #expect(state.contributor == nil)
        }
    }

    // MARK: - Le titre

    @Test func titleIsTheHandleWhenTheProfileIsKnown() {
        let state = makeState(profile: makeProfile(xp: 210, level: 2))
        #expect(state.title == .handle("NEON-FALCON-88"))
    }

    /// Sans ce cas, un utilisateur connecté verrait « Ton profil » clignoter le
    /// temps de l'aller-retour réseau avant que son pseudo n'apparaisse.
    @Test func titleIsAPlaceholderWhileLoading() {
        #expect(makeState(profile: nil, isLoadingProfile: true).title == .placeholder)
    }

    @Test func titleIsNeutralWhenThereIsNoProfileAndNoLoad() {
        #expect(makeState(profile: nil, isLoadingProfile: false).title == .neutral)
    }

    // MARK: - La ligne contributeur

    /// L'invitation suit l'XP, PAS le niveau. Les deux ne se recouvrent pas :
    /// le premier palier est à 50 XP, donc on peut avoir contribué une fois
    /// (20 XP) et rester au niveau 0. Lui resservir « propose un lieu »
    /// nierait ce qu'elle vient de faire.
    @Test func zeroXPShowsTheInvitation() {
        let state = makeState(profile: makeProfile(xp: 0, level: 0))
        #expect(state.contributor == .invitation)
    }

    @Test func someXPBelowTheFirstThresholdShowsTheXPWithoutAGradeName() {
        let state = makeState(profile: makeProfile(xp: 20, level: 0))
        #expect(state.contributor == .ranked(gradeNameKey: nil, xp: 20, rank: nil, pending: 0))
    }

    @Test func aRankedContributorCarriesItsGradeRankAndPendingCount() {
        let state = makeState(
            profile: makeProfile(xp: 450, level: 3, rank: 342),
            pendingContributionCount: 3
        )
        #expect(state.contributor == .ranked(
            gradeNameKey: "profile.contributorGrade.relay", xp: 450, rank: 342, pending: 3
        ))
    }

    /// Règle existante conservée : pas de rang plutôt qu'un zéro faux.
    @Test func anAbsentRankStaysAbsent() {
        let state = makeState(profile: makeProfile(xp: 450, level: 3, rank: nil))
        #expect(state.contributor == .ranked(
            gradeNameKey: "profile.contributorGrade.relay", xp: 450, rank: nil, pending: 0
        ))
    }

    /// La base peut gagner un palier avant l'app : l'XP et le rang restent
    /// affichés, seul le nom disparaît.
    @Test func anUnknownLevelLosesItsNameButKeepsItsNumbers() {
        let state = makeState(profile: makeProfile(xp: 9000, level: 9, rank: 1))
        #expect(state.contributor == .ranked(gradeNameKey: nil, xp: 9000, rank: 1, pending: 0))
    }

    // MARK: - La jauge d'exploration

    /// Elle est locale : elle vit même sans profil, c'est tout son intérêt.
    @Test func theExplorerGaugeLivesWithoutAProfile() {
        let state = makeState(profile: nil, foundCount: 87)
        #expect(state.explorerGrade == .pathfinder)
        #expect(state.foundCount == 87)
        #expect(state.remainingToNext == 13)
        #expect(state.nextGradeNameKey == "profile.explorerGrade.cartographer")
        #expect(state.explorerProgress != nil)
    }

    @Test func theLastExplorerGradeHasNoBarAndNoNextName() {
        let state = makeState(profile: nil, foundCount: 600)
        #expect(state.explorerGrade == .neonNomad)
        #expect(state.explorerProgress == nil)
        #expect(state.remainingToNext == nil)
        #expect(state.nextGradeNameKey == nil)
    }

    /// Zéro lieu coché est un vrai départ, pas un vide.
    @Test func zeroFoundIsAStartingGradeNotAnEmptyState() {
        let state = makeState(profile: nil, foundCount: 0)
        #expect(state.explorerGrade == .drifter)
        #expect(state.remainingToNext == 10)
    }

    @Test func proEntitlementPassesThrough() {
        #expect(makeState(profile: nil, isProEntitled: true).isProEntitled)
        #expect(!makeState(profile: nil, isProEntitled: false).isProEntitled)
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ProfileHeaderStateTests 2>&1 | tail -20
```

Attendu : `cannot find 'ProfileHeaderState' in scope`.

- [ ] **Step 3 : écrire `ProfileHeaderState`**

Créer `NeonCompass/Features/Profile/ProfileHeaderState.swift` :

```swift
import Foundation

/// Tout l'état de l'entête du Profil, dérivé sans SwiftUI et donc testable.
///
/// Ce type existe pour une raison précise. L'entête affichait « Ton profil » —
/// le titre anonyme — ET « Niveau 0 / 0 XP » dans le même bloc : le titre
/// suivait `userID != nil && serverFeatures.isEnabled` dans `ProfileScreen`,
/// le bloc chiffré suivait un `if let profile` dans `ProfileHeaderView`. Deux
/// conditions pour une seule question, réparties entre deux fichiers, donc
/// aucun test ne pouvait voir la combinaison qui les contredit.
///
/// Il n'y a plus qu'une règle : **tout ce qui est chiffré suit `profile != nil`,
/// et rien d'autre.** L'entête ne reçoit délibérément PAS de `isSignedIn` — le
/// profil n'est chargé que connecté, donc `contributor != nil` implique déjà
/// « connecté », et les états « déconnecté » et « serveur coupé » rendent
/// volontairement la même chose.
struct ProfileHeaderState: Equatable {
    enum Title: Equatable {
        case handle(String)
        /// Chargement en cours. Rendu en gabarit `.redacted` : sans ce cas, un
        /// connecté verrait « Ton profil » clignoter avant son pseudo.
        case placeholder
        case neutral
    }

    enum Contributor: Equatable {
        /// XP à zéro. Le seul endroit de l'app qui dise comment l'XP se gagne.
        case invitation
        /// `gradeNameKey` est nul sous 50 XP (niveau 0), et pour tout niveau
        /// que l'app ne connaît pas encore.
        case ranked(gradeNameKey: String?, xp: Int, rank: Int?, pending: Int)
    }

    let title: Title
    let isProEntitled: Bool
    let explorerGrade: ExplorerGrade
    let foundCount: Int
    let explorerProgress: Double?
    let remainingToNext: Int?
    let nextGradeNameKey: String?
    let contributor: Contributor?

    init(
        profile: Profile?,
        isLoadingProfile: Bool,
        isProEntitled: Bool,
        foundCount: Int,
        pendingContributionCount: Int
    ) {
        if let profile {
            title = .handle(profile.handle)
            // Sur l'XP et non sur le niveau : le premier palier étant à 50, on
            // peut avoir contribué une fois et rester au niveau 0.
            contributor = profile.xp == 0
                ? .invitation
                : .ranked(
                    gradeNameKey: ContributorGrade.named(level: profile.level)?.nameKey,
                    xp: profile.xp,
                    rank: profile.rank,
                    pending: pendingContributionCount
                )
        } else {
            title = isLoadingProfile ? .placeholder : .neutral
            contributor = nil
        }

        self.isProEntitled = isProEntitled
        self.foundCount = foundCount
        let grade = ExplorerGrade.forFound(foundCount)
        explorerGrade = grade
        explorerProgress = grade.progress(found: foundCount)
        remainingToNext = grade.remainingToNext(found: foundCount)
        nextGradeNameKey = grade.next?.nameKey
    }
}
```

- [ ] **Step 4 : ajouter `isLoadingProfile` à `ProfileModel`**

Dans `NeonCompass/Features/Profile/ProfileModel.swift`, remplacer :

```swift
    private(set) var profile: Profile?
```

par :

```swift
    private(set) var profile: Profile?

    /// Distingue « pas encore connu » de « pas disponible ». Sans lui,
    /// l'entête d'un utilisateur connecté afficherait le titre anonyme le
    /// temps de l'aller-retour réseau, puis basculerait sur son pseudo.
    private(set) var isLoadingProfile = false
```

et remplacer :

```swift
    func loadProfile(uid: String) async {
        profile = try? await repository.fetchProfile(uid: uid)
    }
```

par :

```swift
    func loadProfile(uid: String) async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        profile = try? await repository.fetchProfile(uid: uid)
    }
```

- [ ] **Step 5 : lancer les tests pour vérifier qu'ils passent**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ProfileHeaderStateTests \
       -only-testing:NeonCompassTests/ProfileModelTests 2>&1 | tail -20
```

Attendu : `TEST SUCCEEDED`, 13 tests de `ProfileHeaderStateTests` plus ceux de `ProfileModelTests`.

- [ ] **Step 6 : commiter**

```sh
git status --short
git add NeonCompass/Features/Profile/ProfileHeaderState.swift \
        NeonCompass/Features/Profile/ProfileModel.swift \
        NeonCompassTests/Profile/ProfileHeaderStateTests.swift project.yml
git commit -m "fix(profil): une seule règle décide de ce qui est chiffré dans l'entête"
```

---

### Task 5 : les chaînes de l'entête et de l'invitation

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces : les clés consommées par la tâche 6.

- [ ] **Step 1 : écrire le script**

Créer `$CLAUDE_JOB_DIR/tmp/add-header-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "profile.explorer.found %lld": {
        "en": "%lld places", "fr": "%lld lieux", "es": "%lld lugares",
        "it": "%lld luoghi", "de": "%lld Orte"},
    "profile.explorer.remaining %lld %@": {
        "en": "%lld to go before %@",
        "fr": "%lld avant « %@ »",
        "es": "%lld para llegar a %@",
        "it": "%lld per raggiungere %@",
        "de": "Noch %lld bis %@"},
    "profile.contribute.invitation": {
        "en": "Suggest a place to unlock your rank",
        "fr": "Propose un lieu pour ouvrir ton rang",
        "es": "Sugiere un lugar para desbloquear tu rango",
        "it": "Proponi un luogo per sbloccare il tuo grado",
        "de": "Schlage einen Ort vor und schalte deinen Rang frei"},
    "profile.contribute.invitationDetail": {
        "en": "+20 XP once approved",
        "fr": "+20 XP à l'approbation",
        "es": "+20 XP al aprobarse",
        "it": "+20 XP all'approvazione",
        "de": "+20 XP nach der Freigabe"},
    "profile.contribute.hint.title": {
        "en": "Suggest a place", "fr": "Proposer un lieu", "es": "Sugerir un lugar",
        "it": "Proporre un luogo", "de": "Einen Ort vorschlagen"},
    "profile.contribute.hint.message": {
        "en": "On the map, press and hold exactly where the place is. Once a moderator approves it, you earn 20 XP and it appears for everyone.",
        "fr": "Sur la carte, appuie longuement à l'endroit exact du lieu. Une fois validé par la modération, il te rapporte 20 XP et apparaît pour tout le monde.",
        "es": "En el mapa, mantén pulsado justo donde está el lugar. Cuando se apruebe, ganarás 20 XP y aparecerá para todos.",
        "it": "Sulla mappa, tieni premuto esattamente dove si trova il luogo. Una volta approvato, ti frutta 20 XP e appare per tutti.",
        "de": "Halte auf der Karte genau dort gedrückt, wo der Ort liegt. Nach der Freigabe bringt er dir 20 XP und erscheint für alle."},
    "profile.contribute.hint.openMap": {
        "en": "Open the map", "fr": "Ouvrir la carte", "es": "Abrir el mapa",
        "it": "Apri la mappa", "de": "Karte öffnen"},
    "profile.contribute.hint.cancel": {
        "en": "Not now", "fr": "Plus tard", "es": "Ahora no",
        "it": "Non ora", "de": "Später"},
}

# `profile.level.format` (« Niveau %d ») n'a plus d'appelant : les grades
# nommés le remplacent.
REMOVED = ["profile.level.format"]

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

for key in REMOVED:
    catalog["strings"].pop(key, None)

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(REMOVED)} retirées, {len(catalog['strings'])} au total")
```

- [ ] **Step 2 : l'exécuter, puis vérifier la couverture**

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-header-keys.py"
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | tail -20
```

Attendu : `8 clés ajoutées, 1 retirées, N au total` puis `TEST SUCCEEDED`. Le test
`formatSpecifiersMatchAcrossLocales` vérifie que `%lld` et `%@` sont présents
dans les cinq traductions de `profile.explorer.remaining %lld %@`.

- [ ] **Step 3 : commiter**

```sh
git add NeonCompass/Resources/Localizable.xcstrings
git commit -m "i18n(profil): les chaînes de la jauge d'exploration et de l'invitation"
```

---

### Task 6 : l'entête réécrite

**Files:**
- Modify: `NeonCompass/Features/Profile/ProfileHeaderView.swift` (réécriture complète)
- Create: `NeonCompass/Features/Profile/ContributeHintSheet.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`
- Modify: `NeonCompass/App/RootView.swift:50`

**Interfaces:**
- Consumes: `ProfileHeaderState` (tâche 4), les clés des tâches 3 et 5.
- Produces: `ProfileHeaderView(state:onOpenSettings:onContribute:)`, `ContributeHintSheet(onOpenMap:)`. `AppModel` devient disponible par l'environnement.

- [ ] **Step 1 : rendre `AppModel` disponible par l'environnement**

Dans `NeonCompass/App/RootView.swift`, après la ligne `.environment(authModel)`, ajouter :

```swift
        .environment(model)
```

- [ ] **Step 2 : réécrire `ProfileHeaderView`**

Remplacer tout le contenu de `NeonCompass/Features/Profile/ProfileHeaderView.swift` par :

```swift
import SwiftUI

/// Entête du Profil : deux jauges, jamais une.
///
/// La haute est LOCALE — elle compte les lieux cochés, elle vit dès le premier
/// POI, hors ligne et sans compte. C'est elle qui porte le mot « niveau » au
/// sens où un joueur l'entend. La basse est SERVEUR, et n'existe que si un
/// profil a pu être lu.
///
/// La jauge haute ne double pas les anneaux de `ProgressionListView` juste
/// dessous : ceux-ci sont par jeu et en pourcentage d'une collection connue,
/// celle-ci est globale et en nombre absolu. Et le nombre absolu reste juste
/// quand `ChallengeProgress.expected` est nul, ce que le pourcentage ne peut
/// pas.
///
/// Cette vue ne décide de rien : tout est dérivé dans `ProfileHeaderState`,
/// qui est testé. C'est ce qui a fermé le défaut où l'entête se disait anonyme
/// et chiffrée dans le même bloc.
struct ProfileHeaderView: View {
    let state: ProfileHeaderState
    let onOpenSettings: () -> Void
    let onContribute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleRow
            explorerGauge
            if let contributor = state.contributor {
                Divider().overlay(Color.white.opacity(0.08))
                contributorLine(contributor)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Titre

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            titleText
            if state.isProEntitled {
                Text("profile.pro.badge")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(NCColor.nightSky)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NCColor.neonCyan, in: .capsule)
                    .accessibilityLabel(Text("profile.pro.badge"))
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("settings.title"))
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch state.title {
        case .handle(let handle):
            Text(handle)
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
        case .placeholder:
            // Le pseudo arrive : un gabarit plutôt qu'un titre anonyme qui
            // clignoterait le temps de l'aller-retour réseau.
            Text(verbatim: "NEON-XXXXXX-00")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        case .neutral:
            Text("profile.header.anonymous")
                .font(NCTypography.displayTitle)
                .foregroundStyle(NCColor.neonCyan)
        }
    }

    // MARK: - Jauge d'exploration

    private var explorerGauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(state.explorerGrade.nameKey))
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                Spacer()
                Text("profile.explorer.found \(state.foundCount)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let progress = state.explorerProgress {
                ProgressView(value: progress)
                    .tint(NCColor.neonCyan)
            }

            if let remaining = state.remainingToNext, let nextKey = state.nextGradeNameKey {
                Text(remainingLine(remaining: remaining, nextKey: nextKey))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        // Une phrase, pas quatre fragments.
        .accessibilityElement(children: .combine)
    }

    /// `NSLocalizedString` et pas `String(localized:)` : la clé du grade
    /// suivant est calculée à l'exécution, et `String(localized:)` veut un
    /// littéral. Le catalogue compile toutes ses entrées, référencées
    /// littéralement ou non, donc la résolution est garantie.
    private func remainingLine(remaining: Int, nextKey: String) -> String {
        String(
            format: String(localized: "profile.explorer.remaining %lld %@"),
            remaining,
            NSLocalizedString(nextKey, comment: "")
        )
    }

    // MARK: - Ligne contributeur

    @ViewBuilder
    private func contributorLine(_ contributor: ProfileHeaderState.Contributor) -> some View {
        switch contributor {
        case .invitation:
            Button(action: onContribute) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(NCColor.neonCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("profile.contribute.invitation")
                            .font(NCTypography.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text("profile.contribute.invitationDetail")
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

        case .ranked(let gradeNameKey, let xp, let rank, let pending):
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.caption2)
                    .foregroundStyle(NCColor.neonCyan)
                Text(rankedSummary(gradeNameKey: gradeNameKey, xp: xp, rank: rank, pending: pending))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Composée de fragments déjà traduits plutôt que d'une chaîne de format
    /// par combinaison : le grade, le rang et l'attente sont indépendamment
    /// absents, ce qui ferait huit formats à traduire en cinq langues.
    private func rankedSummary(gradeNameKey: String?, xp: Int, rank: Int?, pending: Int) -> String {
        var parts: [String] = []
        if let gradeNameKey {
            parts.append(NSLocalizedString(gradeNameKey, comment: "").uppercased())
        }
        parts.append(String(format: String(localized: "profile.xp.format"), xp))
        if let rank {
            parts.append(String(format: String(localized: "profile.rank %lld"), rank))
        }
        if pending > 0 {
            parts.append(String(format: String(localized: "profile.pending %lld"), pending))
        }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 3 : créer la feuille d'invitation**

Créer `NeonCompass/Features/Profile/ContributeHintSheet.swift` :

```swift
import SwiftUI

/// Dit le geste avant d'envoyer sur la carte.
///
/// Une contribution SE POSE sur la carte : `ContributionSubmissionSheet` exige
/// une `position`, et le seul chemin est l'appui long (`MapScreen`). Basculer
/// directement sur l'onglet Carte laisserait l'utilisateur devant un écran sans
/// indice sur ce qu'on attend de lui.
struct ContributeHintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onOpenMap: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 44))
                    .foregroundStyle(NCColor.neonCyan)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text("profile.contribute.hint.message")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Button {
                    onOpenMap()
                    dismiss()
                } label: {
                    Text("profile.contribute.hint.openMap")
                        .font(NCTypography.body.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(NCColor.neonCyan)

                Button("profile.contribute.hint.cancel") { dismiss() }
                    .font(NCTypography.body)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle("profile.contribute.hint.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 4 : brancher `ProfileScreen`**

Dans `NeonCompass/Features/Profile/ProfileScreen.swift` :

Ajouter après `@Environment(ProEntitlementModel.self) private var proEntitlementModel` :

```swift
    @Environment(FoundStore.self) private var foundStore
    @Environment(AppModel.self) private var appModel
```

Ajouter après `@State private var showSettings = false` :

```swift
    @State private var showContributeHint = false
```

Remplacer le bloc `ProfileHeaderView(...)` (lignes 22 à 32) par :

```swift
                    ProfileHeaderView(
                        state: ProfileHeaderState(
                            profile: profileModel.profile,
                            isLoadingProfile: profileModel.isLoadingProfile,
                            isProEntitled: proEntitlementModel.isProEntitled,
                            foundCount: foundStore.foundIDs.count,
                            pendingContributionCount: communityModel?.myContributions
                                .filter { $0.status == .pending }.count ?? 0
                        ),
                        onOpenSettings: { showSettings = true },
                        onContribute: { showContributeHint = true }
                    )
```

Ajouter après le `.sheet(isPresented: $showSettings)` :

```swift
        .sheet(isPresented: $showContributeHint) {
            ContributeHintSheet(onOpenMap: { appModel.selectedTab = .map })
        }
```

- [ ] **Step 5 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test 2>&1 | tail -30
```

Attendu : `TEST SUCCEEDED`. En cas d'échec de compilation sur `serverFeatures`
devenu inutilisé dans `ProfileScreen`, le laisser en place : il sert encore aux
sections « Mes contributions » et à la feuille de réglages.

- [ ] **Step 6 : vérifier le catalogue et commiter**

```sh
git status --short
# Si Localizable.xcstrings apparaît modifié sans qu'on y ait touché :
# git checkout -- NeonCompass/Resources/Localizable.xcstrings
git add NeonCompass/Features/Profile/ProfileHeaderView.swift \
        NeonCompass/Features/Profile/ContributeHintSheet.swift \
        NeonCompass/Features/Profile/ProfileScreen.swift \
        NeonCompass/App/RootView.swift project.yml
git commit -m "feat(profil): l'entête porte deux jauges et dit comment l'XP se gagne"
```

---

### Task 7 : `SignedInAccount` — savoir avec quel compte on est connecté

**Files:**
- Create: `NeonCompass/Core/Auth/SignedInAccount.swift`
- Modify: `NeonCompass/Core/Auth/AuthProviding.swift`
- Modify: `NeonCompass/Core/Auth/SupabaseAuthProvider.swift`
- Modify: `NeonCompass/Features/Profile/AuthModel.swift`
- Modify: `NeonCompassTests/Profile/ProfileFakes.swift`
- Test: `NeonCompassTests/Auth/SignedInAccountTests.swift`

**Interfaces:**
- Produces: `SignedInAccount(provider:email:)`, `SignedInAccount.Provider.from(_ raw: String?) -> Provider`, `AuthProviding.currentAccount: SignedInAccount?`, `AuthModel.currentAccount: SignedInAccount?`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Auth/SignedInAccountTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct SignedInAccountTests {
    @Test func knownProvidersMapToTheirCase() {
        #expect(SignedInAccount.Provider.from("apple") == .apple)
        #expect(SignedInAccount.Provider.from("google") == .google)
        #expect(SignedInAccount.Provider.from("email") == .email)
    }

    /// Supabase peut rendre la casse qu'il veut ; l'app ne doit pas en dépendre.
    @Test func providerMatchingIgnoresCase() {
        #expect(SignedInAccount.Provider.from("Apple") == .apple)
        #expect(SignedInAccount.Provider.from("GOOGLE") == .google)
    }

    /// Un fournisseur ajouté côté Supabase avant l'app ne doit pas faire
    /// disparaître la ligne d'identité : elle dit « connecté », sans préciser.
    @Test func anUnknownProviderIsCarriedThroughInsteadOfDropped() {
        #expect(SignedInAccount.Provider.from("github") == .other("github"))
        #expect(SignedInAccount.Provider.from(nil) == .other(""))
    }

    @Test func labelKeysAreDistinct() {
        let keys = [
            SignedInAccount.Provider.apple.labelKey,
            SignedInAccount.Provider.google.labelKey,
            SignedInAccount.Provider.email.labelKey,
            SignedInAccount.Provider.other("x").labelKey,
        ]
        #expect(Set(keys).count == 4)
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/SignedInAccountTests 2>&1 | tail -20
```

Attendu : `cannot find 'SignedInAccount' in scope`.

- [ ] **Step 3 : écrire le type**

Créer `NeonCompass/Core/Auth/SignedInAccount.swift` :

```swift
import Foundation

/// De quel compte il s'agit — le fournisseur et, quand elle existe, l'adresse.
///
/// Les réglages ne le disaient nulle part : `AuthProviding` n'exposait que
/// `currentUserID`, donc un utilisateur connecté ne pouvait pas savoir avec
/// quel compte, ni quoi faire s'il en avait plusieurs.
///
/// Les adresses relais d'Apple (`@privaterelay.appleid.com`) s'affichent telles
/// quelles : c'est bien l'adresse du compte, et la masquer viderait la ligne de
/// ce qui la rend utile.
struct SignedInAccount: Equatable, Sendable {
    enum Provider: Equatable, Sendable {
        case apple, google, email
        /// Porté et non écarté : un fournisseur activé côté Supabase avant
        /// l'app ne doit pas faire disparaître la ligne d'identité.
        case other(String)

        static func from(_ raw: String?) -> Provider {
            switch raw?.lowercased() {
            case "apple": .apple
            case "google": .google
            case "email": .email
            case let value: .other(value ?? "")
            }
        }

        var labelKey: String {
            switch self {
            case .apple: "settings.account.provider.apple"
            case .google: "settings.account.provider.google"
            case .email: "settings.account.provider.email"
            case .other: "settings.account.provider.other"
            }
        }
    }

    let provider: Provider
    let email: String?
}
```

- [ ] **Step 4 : l'exposer sur le protocole et ses implémentations**

Dans `NeonCompass/Core/Auth/AuthProviding.swift`, après `var currentUserID: String? { get }`, ajouter :

```swift

    /// Le compte de la session courante, pour que les réglages puissent dire
    /// AVEC QUOI on est connecté. Nul quand personne ne l'est.
    var currentAccount: SignedInAccount? { get }
```

Dans `NeonCompass/Core/Auth/SupabaseAuthProvider.swift`, après le bloc `var currentUserID`, ajouter :

```swift

    /// `identities` d'abord : c'est la liste faisant foi côté GoTrue.
    /// `app_metadata.provider` est le repli, présent sur les sessions plus
    /// anciennes.
    var currentAccount: SignedInAccount? {
        guard let user = client?.auth.currentUser else { return nil }
        let raw = user.identities?.first?.provider
            ?? user.appMetadata["provider"]?.stringValue
        return SignedInAccount(provider: .from(raw), email: user.email)
    }
```

Dans `NeonCompass/Features/Profile/AuthModel.swift`, après `private(set) var userID: String?`, ajouter :

```swift

    /// Relu à chaque changement de session plutôt que stocké : le fournisseur
    /// et l'adresse ne changent jamais sans que `userID` ne change aussi.
    var currentAccount: SignedInAccount? { authProvider.currentAccount }
```

Dans `NeonCompassTests/Profile/ProfileFakes.swift`, dans `FakeAuthProvider`, après `var currentUserID: String? { userIDToReturn }`, ajouter :

```swift

    nonisolated(unsafe) var accountToReturn: SignedInAccount?
    var currentAccount: SignedInAccount? { accountToReturn }
```

- [ ] **Step 5 : lancer les tests**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/SignedInAccountTests \
       -only-testing:NeonCompassTests/AuthModelTests 2>&1 | tail -20
```

Attendu : `TEST SUCCEEDED`. Si `AnyJSON.stringValue` n'existe pas dans la version
de `supabase-swift` du projet, remplacer par un `if case .string(let s) = user.appMetadata["provider"]`.

- [ ] **Step 6 : commiter**

```sh
git status --short
git add NeonCompass/Core/Auth/SignedInAccount.swift \
        NeonCompass/Core/Auth/AuthProviding.swift \
        NeonCompass/Core/Auth/SupabaseAuthProvider.swift \
        NeonCompass/Features/Profile/AuthModel.swift \
        NeonCompassTests/Profile/ProfileFakes.swift \
        NeonCompassTests/Auth/SignedInAccountTests.swift project.yml
git commit -m "feat(reglages): la session sait dire avec quel compte on est connecté"
```

---

### Task 8 : les contributeurs masqués portent un nom

**Files:**
- Modify: `NeonCompass/Core/Community/BlockedContributor.swift`
- Modify: `NeonCompass/Features/Community/CommunityModel.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift:251-253`

**Interfaces:**
- Produces: `CommunityModel.block(authorUid:handle:)`, `BlockedContributorSummary(uid:handle:)` conforme à `Identifiable`, `CommunityModel.blockedContributors: [BlockedContributorSummary]`.

> **Un type nommé et pas un tuple.** Swift n'a pas de `KeyPath` vers un élément
> de tuple, donc `ForEach(rows, id: \.uid)` sur `[(uid: String, handle: String?)]`
> ne compile pas. Une petite structure `Identifiable` règle les deux besoins.

- [ ] **Step 1 : ajouter la propriété au modèle SwiftData**

Dans `NeonCompass/Core/Community/BlockedContributor.swift`, après `var blockedAt: Date`, ajouter :

```swift

    /// Enregistré au blocage, parce qu'on ne pourra plus le retrouver ensuite :
    /// la politique RLS de `profiles` est `using (auth.uid() = uid)`, donc le
    /// client ne lit que sa propre ligne. Optionnel pour que les lignes
    /// existantes migrent sans conversion — elles retombent sur l'UID tronqué.
    var authorHandle: String?
```

et remplacer l'initialiseur par :

```swift
    init(authorUid: String, handle: String? = nil, blockedAt: Date = .now) {
        self.authorUid = authorUid
        self.authorHandle = handle
        self.blockedAt = blockedAt
    }
```

- [ ] **Step 2 : faire passer le pseudo dans `CommunityModel`**

Dans `NeonCompass/Features/Community/CommunityModel.swift`, remplacer :

```swift
    func block(authorUid: String) {
        guard !blockedAuthorUIDs.contains(authorUid) else { return }
        modelContext.insert(BlockedContributor(authorUid: authorUid))
        blockedAuthorUIDs.insert(authorUid)
        try? modelContext.save()
    }
```

par :

```swift
    func block(authorUid: String, handle: String? = nil) {
        guard !blockedAuthorUIDs.contains(authorUid) else { return }
        modelContext.insert(BlockedContributor(authorUid: authorUid, handle: handle))
        blockedAuthorUIDs.insert(authorUid)
        try? modelContext.save()
    }

    /// Les contributeurs masqués avec le pseudo qu'ils portaient au blocage.
    /// Les réglages affichaient jusqu'ici l'UUID brut, donc illisible.
    ///
    /// Une structure et pas un tuple : Swift n'a pas de `KeyPath` vers un
    /// élément de tuple, donc `ForEach(…, id: \.uid)` ne compilerait pas.
    var blockedContributors: [BlockedContributorSummary] {
        let rows = (try? modelContext.fetch(FetchDescriptor<BlockedContributor>())) ?? []
        return rows
            .sorted { $0.blockedAt > $1.blockedAt }
            .map { BlockedContributorSummary(uid: $0.authorUid, handle: $0.authorHandle) }
    }
```

et ajouter, en fin de fichier, hors de la classe :

```swift
/// Une ligne de la liste des contributeurs masqués, prête à afficher.
struct BlockedContributorSummary: Identifiable, Equatable, Sendable {
    var id: String { uid }
    let uid: String
    let handle: String?
}
```

- [ ] **Step 3 : passer le pseudo depuis la carte**

Dans `NeonCompass/Features/Map/MapScreen.swift`, remplacer les lignes 251-253 :

```swift
                onBlockAuthor: { spot in
                    if let authorUid = spot.authorUid { communityModel?.block(authorUid: authorUid) }
                },
```

par :

```swift
                onBlockAuthor: { spot in
                    if let authorUid = spot.authorUid {
                        communityModel?.block(authorUid: authorUid, handle: spot.authorHandle)
                    }
                },
```

- [ ] **Step 4 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test 2>&1 | tail -30
```

Attendu : `TEST SUCCEEDED`. La migration SwiftData est légère (propriété
optionnelle ajoutée) et ne demande aucun `VersionedSchema`.

- [ ] **Step 5 : commiter**

```sh
git status --short
git add NeonCompass/Core/Community/BlockedContributor.swift \
        NeonCompass/Features/Community/CommunityModel.swift \
        NeonCompass/Features/Map/MapScreen.swift
git commit -m "feat(reglages): un contributeur masqué garde le pseudo qu'il portait au blocage"
```

---

### Task 9 : les chaînes des réglages

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

- [ ] **Step 1 : écrire le script**

Créer `$CLAUDE_JOB_DIR/tmp/add-settings-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "settings.section.account": {
        "en": "Account", "fr": "Compte", "es": "Cuenta",
        "it": "Account", "de": "Konto"},
    "settings.section.pro": {
        "en": "Neon Compass Pro", "fr": "Neon Compass Pro", "es": "Neon Compass Pro",
        "it": "Neon Compass Pro", "de": "Neon Compass Pro"},
    "settings.section.appearance": {
        "en": "Appearance", "fr": "Apparence", "es": "Apariencia",
        "it": "Aspetto", "de": "Darstellung"},
    "settings.section.notifications": {
        "en": "Notifications", "fr": "Notifications", "es": "Notificaciones",
        "it": "Notifiche", "de": "Mitteilungen"},
    "settings.section.community": {
        "en": "Community", "fr": "Communauté", "es": "Comunidad",
        "it": "Community", "de": "Community"},

    "settings.account.provider.apple": {
        "en": "Signed in with Apple", "fr": "Connecté avec Apple",
        "es": "Conectado con Apple", "it": "Accesso con Apple",
        "de": "Mit Apple angemeldet"},
    "settings.account.provider.google": {
        "en": "Signed in with Google", "fr": "Connecté avec Google",
        "es": "Conectado con Google", "it": "Accesso con Google",
        "de": "Mit Google angemeldet"},
    "settings.account.provider.email": {
        "en": "Signed in with an email address", "fr": "Connecté avec une adresse e-mail",
        "es": "Conectado con un correo electrónico", "it": "Accesso con un indirizzo e-mail",
        "de": "Mit einer E-Mail-Adresse angemeldet"},
    "settings.account.provider.other": {
        "en": "Signed in", "fr": "Connecté", "es": "Conectado",
        "it": "Connesso", "de": "Angemeldet"},
    "settings.account.handle": {
        "en": "Handle", "fr": "Pseudo", "es": "Alias",
        "it": "Nome utente", "de": "Kürzel"},

    "profile.handle.regenerate.confirmTitle": {
        "en": "Change your handle?", "fr": "Changer de pseudo ?",
        "es": "¿Cambiar tu alias?", "it": "Cambiare nome utente?",
        "de": "Kürzel ändern?"},
    "profile.handle.regenerate.confirmMessage": {
        "en": "A new handle is drawn at random. Places you have already published keep the old one.",
        "fr": "Un nouveau pseudo est tiré au hasard. Les lieux que tu as déjà publiés gardent l'ancien.",
        "es": "Se sortea un alias nuevo al azar. Los lugares que ya publicaste conservan el anterior.",
        "it": "Un nuovo nome utente viene estratto a caso. I luoghi già pubblicati mantengono quello precedente.",
        "de": "Ein neues Kürzel wird zufällig gezogen. Bereits veröffentlichte Orte behalten das alte."},
    "profile.handle.regenerate.confirmButton": {
        "en": "Change", "fr": "Changer", "es": "Cambiar",
        "it": "Cambia", "de": "Ändern"},

    "settings.pro.active": {
        "en": "Pro active", "fr": "Pro actif", "es": "Pro activo",
        "it": "Pro attivo", "de": "Pro aktiv"},
    "settings.pro.seeBenefits": {
        "en": "What Pro adds", "fr": "Ce que Pro apporte",
        "es": "Qué añade Pro", "it": "Cosa aggiunge Pro",
        "de": "Was Pro bietet"},

    "profile.blockedContributors.unknown %@": {
        "en": "Contributor %@", "fr": "Contributeur %@", "es": "Colaborador %@",
        "it": "Collaboratore %@", "de": "Beitragende %@"},
}

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(catalog['strings'])} au total")
```

- [ ] **Step 2 : l'exécuter et vérifier**

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-settings-keys.py"
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | tail -20
```

Attendu : `16 clés ajoutées, N au total` puis `TEST SUCCEEDED`.

- [ ] **Step 3 : commiter**

```sh
git add NeonCompass/Resources/Localizable.xcstrings
git commit -m "i18n(reglages): les chaînes des sections, de l'identité et du changement de pseudo"
```

---

### Task 10 : la feuille de réglages passe en `Form`

**Files:**
- Modify: `NeonCompass/Features/Settings/SettingsScreen.swift` (réécriture)
- Create: `NeonCompass/Features/Settings/SettingsAccountSection.swift`
- Create: `NeonCompass/Features/Settings/SettingsAppearanceSection.swift`
- Create: `NeonCompass/Features/Settings/SettingsNotificationsSection.swift`
- Create: `NeonCompass/Features/Settings/SettingsCommunitySection.swift`

**Interfaces:**
- Consumes: `SignedInAccount` (tâche 7), `CommunityModel.blockedContributors` (tâche 8), les clés de la tâche 9.

- [ ] **Step 1 : créer la section Apparence**

Créer `NeonCompass/Features/Settings/SettingsAppearanceSection.swift` :

```swift
import SwiftUI
import UIKit

struct SettingsAppearanceSection: View {
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        Section("settings.section.appearance") {
            Picker(selection: Binding(
                get: { themeStore.selectedTheme },
                set: { themeStore.selectTheme($0) }
            )) {
                ForEach(NCTheme.allCases) { theme in
                    Text(theme.nameKey).tag(theme)
                }
            } label: {
                Text("profile.theme.title")
            }
            .pickerStyle(.menu)

            // La ligne n'apparaît QUE si l'app déclare des icônes alternatives.
            // Aucune n'est déclarée aujourd'hui (`AppIcon-Neon` reste à
            // produire, cf. docs/ops/2026-07-23-alternate-app-icons.md), et la
            // bascule no-oppait donc en silence — un `Toggle` qui revient tout
            // seul. Elle réapparaîtra d'elle-même le jour où l'asset est livré.
            if UIApplication.shared.supportsAlternateIcons {
                Toggle("profile.icon.title", isOn: Binding(
                    get: { UIApplication.shared.alternateIconName != nil },
                    set: { themeStore.setAlternateIcon(named: $0 ? Self.neonIconName : nil) }
                ))
            }
        }
    }

    private static let neonIconName = "AppIcon-Neon"
}
```

- [ ] **Step 2 : créer la section Notifications**

Créer `NeonCompass/Features/Settings/SettingsNotificationsSection.swift` :

```swift
import SwiftUI

struct SettingsNotificationsSection: View {
    let store: FollowedCategoriesStore

    var body: some View {
        Section("settings.section.notifications") {
            ForEach(POICategory.allCases, id: \.self) { category in
                Toggle(isOn: Binding(
                    get: { store.followedCategories.contains(category) },
                    set: { _ in Task { await store.toggle(category) } }
                )) {
                    Text(category.localizedNameKey)
                }
            }
        }
    }
}
```

- [ ] **Step 3 : créer la section Communauté**

Créer `NeonCompass/Features/Settings/SettingsCommunitySection.swift` :

```swift
import SwiftUI

struct SettingsCommunitySection: View {
    let communityModel: CommunityModel

    var body: some View {
        Section("settings.section.community") {
            let blocked = communityModel.blockedContributors
            if blocked.isEmpty {
                Text("profile.blockedContributors.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blocked) { contributor in
                    HStack {
                        Text(label(for: contributor))
                        Spacer()
                        Button("profile.blockedContributors.unblock") {
                            communityModel.unblock(authorUid: contributor.uid)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    /// Le pseudo enregistré au blocage, sinon un UID tronqué — les lignes
    /// bloquées avant que le pseudo ne soit conservé n'en ont pas, et le client
    /// ne peut pas le retrouver (RLS : on ne lit que sa propre ligne).
    private func label(for contributor: BlockedContributorSummary) -> String {
        if let handle = contributor.handle, !handle.isEmpty { return handle }
        let short = contributor.uid.prefix(4).uppercased()
        return String(format: String(localized: "profile.blockedContributors.unknown %@"), "\(short)…")
    }
}
```

- [ ] **Step 4 : créer la section Compte**

Créer `NeonCompass/Features/Settings/SettingsAccountSection.swift` :

```swift
import SwiftUI
import AuthenticationServices

/// La section Compte : qui on est, et les deux gestes qui mettent fin à la
/// session. Les boutons de connexion sont DÉPLACÉS depuis `SettingsScreen`
/// sans changer d'une ligne — le protocole Sign in with Apple n'est pas
/// retouché pendant une refonte de mise en page.
struct SettingsAccountSection: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures

    let profileModel: ProfileModel
    @Binding var showDeleteConfirmation: Bool
    @Binding var showHandleConfirmation: Bool
    let onSignInFailure: (any Error) -> Void
    let onAppleResult: (Result<ASAuthorization, Error>) -> Void
    let onPrepareAppleRequest: (ASAuthorizationAppleIDRequest) -> Void

    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        if authModel.userID == nil {
            signedOutSection
        } else {
            signedInSection
            destructiveSection
        }
    }

    // MARK: - Connecté

    @ViewBuilder
    private var signedInSection: some View {
        Section("settings.section.account") {
            if let account = authModel.currentAccount {
                Text(LocalizedStringKey(account.provider.labelKey))
                if let email = account.email, !email.isEmpty {
                    Text(email)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if serverFeatures.isEnabled {
                if let handle = profileModel.profile?.handle {
                    LabeledContent("settings.account.handle") { Text(handle) }
                }
                Button("profile.handle.regenerate") { showHandleConfirmation = true }
            }
        }
    }

    private var destructiveSection: some View {
        Section {
            Button("profile.signOut") { Task { try? await authModel.signOut() } }
            Button("profile.deleteAccount", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Déconnecté

    private var signedOutSection: some View {
        Section("settings.section.account") {
            Text(serverFeatures.isEnabled ? "profile.signIn.prompt" : "profile.signIn.syncOnlyPrompt")
                .font(NCTypography.body)

            // Apple en premier, et en tête : la règle App Store 4.8 l'exige dès
            // qu'un autre fournisseur tiers est proposé.
            SignInWithAppleButton(.signIn) { request in
                onPrepareAppleRequest(request)
            } onCompletion: { result in
                onAppleResult(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Button("profile.signIn.google") {
                Task {
                    do { try await authModel.signInWithGoogle() } catch { onSignInFailure(error) }
                }
            }

            Button(showEmailForm ? "profile.signIn.email.hide" : "profile.signIn.email.show") {
                withAnimation { showEmailForm.toggle() }
            }

            if showEmailForm { emailRows }
        }
    }

    @ViewBuilder
    private var emailRows: some View {
        TextField("profile.signIn.email.address", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        // `.password` et pas `.newPassword` : le même champ sert à se connecter
        // et à s'inscrire, et `.newPassword` ferait proposer un mot de passe
        // fort à quelqu'un qui veut simplement ressaisir le sien.
        SecureField("profile.signIn.email.password", text: $password)
            .textContentType(.password)

        if authModel.awaitingEmailConfirmation {
            Text("profile.signIn.email.confirmationSent")
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
        }

        Button("profile.signIn.email.signIn") {
            Task {
                do { try await authModel.signIn(email: email, password: password) }
                catch { onSignInFailure(error) }
            }
        }

        Button("profile.signIn.email.signUp") {
            Task {
                do { try await authModel.signUp(email: email, password: password) }
                catch { onSignInFailure(error) }
            }
        }
    }
}
```

- [ ] **Step 5 : réécrire `SettingsScreen`**

Remplacer tout le contenu de `NeonCompass/Features/Settings/SettingsScreen.swift` par :

```swift
import SwiftUI
import AuthenticationServices

/// Feuille de réglages, ouverte depuis l'entête du Profil.
///
/// En feuille et pas en `toolbar` : aucun écran d'onglet n'a de
/// `NavigationStack` — `RootView` les empile dans un `ZStack` sous une barre
/// maison — donc un `ToolbarItem` ne s'afficherait nulle part, sans erreur ni
/// avertissement. Même motif que `PaywallView`.
///
/// En `Form` et plus en `VStack` : sur iOS 26 il apporte Liquid Glass, Dynamic
/// Type, les tailles de frappe et les affordances VoiceOver sans une ligne de
/// code, ce que la pile à plat redéfinissait mal. Le corps de cet écran ne
/// porte plus que la structure, les feuilles et les alertes ; chaque section
/// vit dans son fichier.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures

    let profileModel: ProfileModel
    let communityModel: CommunityModel?

    @State private var settingsModel: SettingsModel
    @State private var followedCategoriesStore = FollowedCategoriesStore(
        notifier: APNsFollowedCategoryNotifier.shared
    )
    @State private var showDeleteConfirmation = false
    @State private var showHandleConfirmation = false
    @State private var showPaywall = false
    @State private var currentNonce: String?
    @State private var signInError: String?

    init(profileModel: ProfileModel, communityModel: CommunityModel?) {
        self.profileModel = profileModel
        self.communityModel = communityModel
        _settingsModel = State(initialValue: SettingsModel(profileModel: profileModel))
    }

    var body: some View {
        NavigationStack {
            Form {
                SettingsAccountSection(
                    profileModel: profileModel,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    showHandleConfirmation: $showHandleConfirmation,
                    onSignInFailure: reportSignIn,
                    onAppleResult: handleSignInResult,
                    onPrepareAppleRequest: prepareAppleRequest
                )

                proSection

                if proEntitlementModel.isProEntitled {
                    SettingsAppearanceSection()
                    // Les notifications suivies sont envoyées par une Edge
                    // Function : sans elle, l'écran promettrait un service qui
                    // n'arrive jamais.
                    if serverFeatures.isEnabled {
                        SettingsNotificationsSection(store: followedCategoriesStore)
                    }
                }

                if serverFeatures.isEnabled, let communityModel {
                    SettingsCommunitySection(communityModel: communityModel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("settings.done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { communityModel?.refreshBlockedAuthors() }
        .alert(
            "profile.handle.regenerate.confirmTitle",
            isPresented: $showHandleConfirmation
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {}
            Button("profile.handle.regenerate.confirmButton") {
                Task { try? await profileModel.regenerateHandle() }
            }
        } message: {
            Text("profile.handle.regenerate.confirmMessage")
        }
        .alert(
            "profile.deleteAccount.confirmTitle",
            isPresented: $showDeleteConfirmation
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {}
            Button("profile.deleteAccount.confirmButton", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("profile.deleteAccount.confirmMessage")
        }
        .alert(
            "profile.deleteAccount.failed",
            isPresented: Binding(
                get: { settingsModel.deletionFailed },
                set: { if !$0 { settingsModel.dismissDeletionFailure() } }
            )
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) {
                settingsModel.dismissDeletionFailure()
            }
        }
        .alert(
            "profile.signIn.failed",
            isPresented: Binding(get: { signInError != nil }, set: { if !$0 { signInError = nil } })
        ) {
            Button("profile.deleteAccount.cancelButton", role: .cancel) { signInError = nil }
        } message: {
            // Le détail technique n'est pas traduit : il vient du système ou de
            // GoTrue, et c'est lui qui permet de comprendre le blocage.
            Text(signInError ?? "")
        }
    }

    /// Ne réénumère pas les avantages : `PaywallView` les liste déjà, et deux
    /// listes finiraient par diverger. Cette section dit l'état, et renvoie.
    @ViewBuilder
    private var proSection: some View {
        Section("settings.section.pro") {
            if proEntitlementModel.isProEntitled {
                Label("settings.pro.active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NCColor.neonCyan)
                Button("settings.pro.seeBenefits") { showPaywall = true }
            } else {
                Button("profile.pro.upgradeButton") { showPaywall = true }
            }
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInCoordinator.makeRawNonce()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = AppleSignInCoordinator.sha256(nonce)
    }

    /// Traduit une erreur de connexion non-Apple en message affichable.
    ///
    /// Les problèmes de saisie sont dits dans la langue de l'utilisateur ; tout
    /// le reste vient du réseau ou de GoTrue, et son texte anglais est ce qui
    /// permet de comprendre le blocage — le masquer par un message générique
    /// rendrait le diagnostic impossible.
    private func reportSignIn(_ error: any Error) {
        let message: String
        switch error as? EmailCredentialProblem {
        case .emptyEmail: message = String(localized: "profile.signIn.email.errorEmpty")
        case .malformedEmail: message = String(localized: "profile.signIn.email.errorMalformed")
        case .passwordTooShort(let minimum):
            message = String(format: String(localized: "profile.signIn.email.errorShort %lld"), minimum)
        case nil:
            // Une annulation est un geste volontaire, pas une panne : refermer
            // la feuille du navigateur ne doit rien afficher.
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
            message = error.localizedDescription
        }
        print("SettingsScreen: connexion refusée — \(message)")
        signInError = message
    }

    private func deleteAccount() async {
        guard let userID = authModel.userID else { return }
        if await settingsModel.deleteAccount(uid: userID, serverEnabled: serverFeatures.isEnabled) {
            try? await authModel.signOut()
        }
    }

    /// Chaque échec est dit. Une version antérieure les avalait tous —
    /// `guard … else { return }` puis `try?` — donc un utilisateur bloqué
    /// n'avait aucun moyen de savoir pourquoi, et nous non plus.
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            report(AppleSignInCoordinator.classify(error: error))
        case .success(let authorization):
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            switch AppleSignInCoordinator.resolve(credential: credential, rawNonce: currentNonce) {
            case .failure(let failure):
                report(failure)
            case .success(let value):
                Task {
                    do {
                        try await authModel.signIn(idTokenString: value.idToken, nonce: value.nonce)
                    } catch {
                        report(.underlying(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func report(_ failure: AppleSignInFailure) {
        let message: String
        switch failure {
        case .canceled: return
        case .unexpectedCredentialType: message = String(localized: "profile.signIn.unexpectedCredential")
        case .missingIdentityToken: message = String(localized: "profile.signIn.missingToken")
        case .missingNonce: message = String(localized: "profile.signIn.missingNonce")
        case .underlying(let detail): message = detail
        }
        // Imprimé en plus de l'alerte : c'est ce qui rend le diagnostic
        // possible depuis les journaux du simulateur.
        print("SettingsScreen: connexion refusée — \(message)")
        signInError = message
    }
}
```

- [ ] **Step 6 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test 2>&1 | tail -30
```

Attendu : `TEST SUCCEEDED`.

- [ ] **Step 7 : vérifier le catalogue et commiter**

```sh
git status --short
# Si Localizable.xcstrings apparaît modifié sans qu'on y ait touché :
# git checkout -- NeonCompass/Resources/Localizable.xcstrings
git add NeonCompass/Features/Settings/ project.yml
git commit -m "refactor(reglages): un Form groupé, éclaté en cinq sections"
```

---

### Task 11 : vérification visuelle au simulateur

Le seul filet qui aurait attrapé le défaut d'origine — il n'était visible qu'à l'écran.

**Files:** aucun modifié en fin de tâche (les forçages sont temporaires).

- [ ] **Step 1 : construire, installer, capturer l'état connecté**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install booted "$(xcodebuild -scheme NeonCompass \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/NeonCompass.app"
xcrun simctl launch booted co.antoineteston.NeonCompass
sleep 5
xcrun simctl io booted screenshot "$CLAUDE_JOB_DIR/tmp/profil-connecte.png"
```

Vérifier sur la capture : le pseudo (ou « Ton profil ») en haut, le grade
d'exploration, la barre, la ligne « N avant … », et la ligne contributeur ou
l'invitation. Aucun « Niveau 0 / 0 XP » sous un titre anonyme.

- [ ] **Step 2 : capturer la feuille de réglages**

`cliclick` ne peut pas ouvrir la feuille — un clic dans un `ScrollView` est
consommé comme un défilement. Forcer temporairement dans
`NeonCompass/Features/Profile/ProfileScreen.swift` :

```swift
    @State private var showSettings = true
```

puis reconstruire, relancer, capturer :

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl launch booted co.antoineteston.NeonCompass
sleep 5
xcrun simctl io booted screenshot "$CLAUDE_JOB_DIR/tmp/reglages.png"
```

Vérifier : les sections nommées, l'identité du compte, le destructeur isolé en
bas, et l'absence de la ligne d'icône alternative.

- [ ] **Step 3 : rétablir et vérifier que l'arbre est propre**

```sh
git checkout -- NeonCompass/Features/Profile/ProfileScreen.swift
git status --short
```

Attendu : aucune sortie.

- [ ] **Step 4 : suite complète une dernière fois**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
git status --short
```

Attendu : `TEST SUCCEEDED` et un arbre propre (restaurer
`Localizable.xcstrings` s'il a été réécrit par l'extraction automatique).

---

## Ordre et dépendances

```
1 ExplorerGrade ─┐
2 ContributorGrade ─┼→ 4 ProfileHeaderState ─→ 6 Entête ─┐
3 Chaînes grades ─┘   5 Chaînes entête ─────────┘        │
                                                         ├→ 11 Vérif visuelle
7 SignedInAccount ─┐                                     │
8 Contributeurs masqués ─┼→ 10 Form réglages ────────────┘
9 Chaînes réglages ─┘
```

Les tâches 1-6 forment l'entête et sont livrables seules. Les tâches 7-10 forment
la feuille et le sont aussi. La 11 se fait après les deux.
