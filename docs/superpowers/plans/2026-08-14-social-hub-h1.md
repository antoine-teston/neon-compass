# Social en hub — palier H1 : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recomposer l'onglet Social en hub à sections : héro « Cette semaine » compact et paginé (VI d'abord), module « À voter », tuile Classement, rebours épinglé, pastille, point d'onglet, mosaïque iPad — en remplacement du sélecteur à segments.

**Architecture:** Un seul flux vertical dans `SocialScreen` ; la logique de visibilité, le rebours compact, l'épinglage et le badge d'onglet sont des types purs testés à part ; les vues complètes s'ouvrent en sheet (compact) ou en panneau latéral (régulier). Aucun changement serveur, de contenu ni de modèle de données — `OnlineEventsModel` gagne seulement deux variantes par-jeu de fonctions existantes.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + Observation, Swift Testing (`import Testing`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-14-social-hub-reagencement-design.md` (palier H1 uniquement — la vitrine Communautés est H2 et n'apparaît nulle part ici).

## Global Constraints

- **Exécution** : branche neuve `feat/social-hub-h1` créée depuis `origin/main` (une tâche = une branche = une PR), dans un worktree isolé (skill `superpowers:using-git-worktrees`).
- iOS/iPadOS **26+**, Swift 6 strict concurrency, **SwiftUI seulement**.
- **Localisation** : toute chaîne visible passe par `NeonCompass/Resources/Localizable.xcstrings`, dans les **cinq** langues `en, fr, es, it, de`. Une clé dont le site d'appel interpole (`Text("clé \(n)")`) doit être nommée **avec son spécificateur** dans le catalogue (`"clé %lld"`) — `LocalizationCoverageTests.interpolatedCallSitesResolveToACatalogKey` le vérifie.
- **IP** : jamais de marque Rockstar dans la prose de l'interface ; le jeu se nomme par `Game.shortLabel` (chiffres romains nus), posé en `Text(verbatim:)`.
- **Design** : chrome Liquid Glass (`.glassEffect`), contenu synthwave ; **3 accents lumineux max par écran** — dans le hub H1 : le rebours (cyan) et la pastille (cyan), rien d'autre ; animer la **commande**, jamais la liste ; ombres bornées (radius ≤ 20, opacité ≤ 0,3).
- **Aucun écran d'onglet n'a de `NavigationStack`** ; les feuilles portent le leur. Un `ToolbarItem` posé sur un écran d'onglet ne s'affiche nulle part.
- **`xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests ».
- **`-only-testing` cible une SUITE, jamais un test seul** (un test seul ne lance rien et rapporte `TEST SUCCEEDED`). Lire la ligne `Test run with N tests` — un compte inattendu vaut échec.
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`** : vérifier `git status` avant chaque commit ; si le fichier est modifié sans qu'on l'ait voulu, `git checkout -- NeonCompass/Resources/Localizable.xcstrings`.
- Bannière publicitaire : uniquement quand du contenu est affiché **et** que l'utilisateur n'est pas Pro ; jamais sur un état vide.
- Simulateurs : `iPhone 17` (iOS 26.5) et `iPad Pro 13-inch (M5)`.
- Commandes :
  ```sh
  xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
  xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/<Suite>
  ```

## Carte des fichiers

| Fichier | Rôle |
|---|---|
| `NeonCompass/Features/Social/SocialHubVisibility.swift` *(créé)* | Visibilité des sections + compte de la pastille (pur) |
| `NeonCompass/Features/Social/WeeklyCountdown.swift` *(créé)* | Décomposition jours/heures/minutes du rebours compact (pur) + `WeeklyCountdownLabel` |
| `NeonCompass/Features/Social/OnlineEventHighlights.swift` *(créé)* | « Ce qui vaut le coup » extrait d'`OnlineEventCard` + compte du « +N » (pur) |
| `NeonCompass/Features/Social/WeeklyHeroCard.swift` *(créé)* | La carte héro compacte d'un jeu |
| `NeonCompass/Features/Social/WeekDetailSheet.swift` *(créé)* | La fiche complète de la semaine (l'`OnlineEventCard` d'avant, en feuille) |
| `NeonCompass/Features/Social/WeeklyHeroPager.swift` *(créé)* | Le glissement horizontal entre jeux, VI d'abord, points de page |
| `NeonCompass/Features/Social/HeroPinning.swift` *(créé)* | Seuil d'épinglage (pur) + `PinnedCountdownChip` |
| `NeonCompass/Features/Social/VoteModule.swift` *(créé)* | Le module « À voter » : 3 propositions, vote inline, pastille, porte « proposer » |
| `NeonCompass/Features/Social/ProposalsSheet.swift` *(créé)* | La vue complète des propositions (l'actuel `ContributionsPanel`, en feuille) |
| `NeonCompass/Features/Social/LeaderboardPodium.swift` *(créé)* | Le podium top 3 (feuille uniquement) |
| `NeonCompass/Features/Social/HubTile.swift` *(créé)* | Le gabarit tuile générique |
| `NeonCompass/Features/Social/LeaderboardTile.swift` *(créé)* | La tuile Classement |
| `NeonCompass/Features/Social/LeaderboardSheet.swift` *(créé)* | La vue complète du classement (podium + liste) |
| `NeonCompass/Features/Social/HubSidePanel.swift` *(créé)* | Le panneau latéral des vues complètes en largeur régulière |
| `NeonCompass/Core/Online/WeekSeenStore.swift` *(créé)* | Persistance « semaine vue » + `SocialTabBadge` (pur) |
| `NeonCompass/Features/Social/SocialScreen.swift` *(récrit)* | L'assemblage du hub ; l'énumération `Panel` disparaît |
| `NeonCompass/Features/Social/LeaderboardSection.swift` *(modifié)* | Gagne `startRank` pour numéroter après le podium |
| `NeonCompass/Features/Social/OnlineEventCard.swift` *(modifié)* | Délègue ses « highlights » au type extrait |
| `NeonCompass/Features/Social/OnlineEventsModel.swift` *(modifié)* | Variantes par-jeu de `currentEvent`/`latestEvent` |
| `NeonCompass/App/AppModel.swift`, `App/CompactTabBar.swift`, `App/RootView.swift` *(modifiés)* | Le point d'onglet Social |

Ce qui **ne bouge pas** : `CommunityModel`, `CommunitiesModel`, `CommunitiesPanel` (réutilisé en H2), `ContributionsPanel` (rhabillé en feuille), `ContributionRow`, `ContributionSections`, `OnlineEventDetailSheet`, `EventReminderScheduler`, repositories, drapeaux, RLS.

## Insertion de clés dans le String Catalog

Plusieurs tâches ajoutent des clés. Toujours par ce script — la sérialisation
`indent=2, separators=(",", ": "), sort_keys=False` + newline final reproduit le
catalogue **octet pour octet** (vérifié le 14/08), et le garde-fou s'arrête si ça
cessait d'être vrai :

```bash
python3 - <<'EOF'
import json, sys
path = "NeonCompass/Resources/Localizable.xcstrings"
raw = open(path, encoding="utf-8").read()
data = json.loads(raw)

def dump(d):
    return json.dumps(d, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n"

if dump(data) != raw:
    sys.exit("Round-trip visuel cassé : insérer les clés à la main dans l'éditeur, ne pas réécrire le fichier.")

def entry(values):
    return {"localizations": {loc: {"stringUnit": {"state": "translated", "value": v}}
                              for loc, v in sorted(values.items())}}

def insert(key, values):
    strings = data["strings"]
    if key in strings:
        return
    items = list(strings.items())
    index = next((i for i, (k, _) in enumerate(items) if k > key), len(items))
    items.insert(index, (key, entry(values)))
    data["strings"] = dict(items)

# --- REMPLACER par les clés de la tâche courante ---
insert("social.hub.exemple", {"en": "…", "fr": "…", "es": "…", "it": "…", "de": "…"})

open(path, "w", encoding="utf-8").write(dump(data))
print("clés insérées")
EOF
```

Après chaque insertion : `git diff --stat NeonCompass/Resources/Localizable.xcstrings`
doit montrer **uniquement des lignes ajoutées** (± 1 ligne de contexte). Un diff qui
touche tout le fichier = round-trip cassé, restaurer et insérer à la main.

---

### Task 1: La visibilité des sections et la pastille (`SocialHubVisibility`)

**Files:**
- Create: `NeonCompass/Features/Social/SocialHubVisibility.swift`
- Test: `NeonCompassTests/Social/SocialHubVisibilityTests.swift`

**Interfaces:**
- Consumes: rien (type pur).
- Produces: `SocialHubVisibility(serverEnabled:proposalCount:leaderboardRowCount:heroShowsEvent:isProEntitled:)` avec `showsVoteModule/showsLeaderboardTile/showsBanner: Bool` ; `SocialHubVisibility.unvotedCount(spotIDs: [String], votedIDs: Set<String>) -> Int`. Consommé par les tâches 6 et 9.

- [ ] **Step 1 : le test qui échoue**

```swift
// NeonCompassTests/Social/SocialHubVisibilityTests.swift
import Testing
@testable import NeonCompass

struct SocialHubVisibilityTests {
    @Test func voteModuleNeedsServerAndProposals() {
        #expect(SocialHubVisibility(serverEnabled: true, proposalCount: 2, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 2, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
        #expect(!SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
    }

    @Test func leaderboardTileNeedsServerAndRows() {
        #expect(SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 3, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
        #expect(!SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 3, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
    }

    /// La règle existante conservée : du contenu affiché ET pas d'abonné Pro.
    /// Un état vide n'est pas un écran de liste, la pub n'y a pas sa place.
    @Test func bannerNeedsAnEventAndNoProEntitlement() {
        #expect(SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsBanner)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: false, isProEntitled: false).showsBanner)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: true).showsBanner)
    }

    @Test func unvotedCountIgnoresVotedSpots() {
        #expect(SocialHubVisibility.unvotedCount(spotIDs: ["a", "b", "c"], votedIDs: ["b"]) == 2)
        #expect(SocialHubVisibility.unvotedCount(spotIDs: [], votedIDs: ["b"]) == 0)
        #expect(SocialHubVisibility.unvotedCount(spotIDs: ["a"], votedIDs: []) == 1)
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/SocialHubVisibilityTests 2>&1 | tail -20`
Expected : échec de **compilation** (`cannot find 'SocialHubVisibility'`). Créer d'abord le fichier de test seul, lancer `xcodegen generate` avant.

- [ ] **Step 3 : l'implémentation minimale**

```swift
// NeonCompass/Features/Social/SocialHubVisibility.swift
import Foundation

/// Quelles sections du hub existent. Type pur : la règle « une section sans
/// contenu disparaît » (la règle `showsGamePicker`, généralisée) se teste ici,
/// pas à l'écran.
struct SocialHubVisibility: Equatable {
    let showsVoteModule: Bool
    let showsLeaderboardTile: Bool
    let showsBanner: Bool

    init(
        serverEnabled: Bool,
        proposalCount: Int,
        leaderboardRowCount: Int,
        heroShowsEvent: Bool,
        isProEntitled: Bool
    ) {
        showsVoteModule = serverEnabled && proposalCount > 0
        showsLeaderboardTile = serverEnabled && leaderboardRowCount > 0
        // La règle existante de l'écran, reprise telle quelle : du contenu
        // affiché, et pas d'abonné Pro. Un état vide n'est pas un écran de liste.
        showsBanner = heroShowsEvent && !isProEntitled
    }

    /// La pastille du module « À voter » : ce que JE n'ai pas encore voté.
    /// Sur des identifiants et non des `Contribution` : c'est ce qui rend le
    /// calcul testable sans fixture.
    static func unvotedCount(spotIDs: [String], votedIDs: Set<String>) -> Int {
        spotIDs.filter { !votedIDs.contains($0) }.count
    }
}
```

- [ ] **Step 4 : `xcodegen generate` puis vérifier le succès**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/SocialHubVisibilityTests 2>&1 | grep -E "Test run|TEST"`
Expected : `Test run with 4 tests passed` puis `TEST SUCCEEDED`.

- [ ] **Step 5 : commit**

```bash
git status --short   # vérifier que Localizable.xcstrings n'a pas bougé
git add NeonCompass/Features/Social/SocialHubVisibility.swift NeonCompassTests/Social/SocialHubVisibilityTests.swift NeonCompass.xcodeproj
git commit -m "feat(social): visibilité des sections du hub et compte de la pastille"
```

---

### Task 2: Le rebours compact (`WeeklyCountdown`)

**Files:**
- Create: `NeonCompass/Features/Social/WeeklyCountdown.swift`
- Test: `NeonCompassTests/Social/WeeklyCountdownTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `WeeklyCountdown(remaining: TimeInterval)` avec `showsDays: Bool`, `days/hours/minutes: Int` ; `WeeklyCountdownLabel(remaining: TimeInterval)` (vue). Consommé par les tâches 4 et 5.

Note d'écart avec la spec, assumée : la spec nomme `Text(timerInterval:)`, qui
rend un format horloge (« 62:14:05 ») illisible au-delà de 24 h. On garde
l'intention — un affichage auto-actualisé sans minuterie Combine — via
`Duration.formatted(.units)` (localisé par le système, donc **aucune clé de
catalogue**) rafraîchi par le `TimelineView(.everyMinute)` que l'écran pose déjà
(tâche 9). La partie testée est le choix des unités.

- [ ] **Step 1 : le test qui échoue**

```swift
// NeonCompassTests/Social/WeeklyCountdownTests.swift
import Testing
@testable import NeonCompass

struct WeeklyCountdownTests {
    @Test func overADayShowsDaysAndHours() {
        let countdown = WeeklyCountdown(remaining: 2 * 86_400 + 14 * 3600 + 30 * 60)
        #expect(countdown.showsDays)
        #expect(countdown.days == 2)
        #expect(countdown.hours == 14)
    }

    /// Le dernier jour, la colonne des jours disparaît — même signal que
    /// `NCCountdownDigits`.
    @Test func lastDayShowsHoursAndMinutes() {
        let countdown = WeeklyCountdown(remaining: 5 * 3600 + 42 * 60)
        #expect(!countdown.showsDays)
        #expect(countdown.hours == 5)
        #expect(countdown.minutes == 42)
    }

    @Test func exactDayBoundaryStillShowsDays() {
        #expect(WeeklyCountdown(remaining: 86_400).showsDays)
        #expect(!WeeklyCountdown(remaining: 86_399).showsDays)
    }

    /// Jamais de chiffres négatifs : l'appelant décide d'afficher « terminé »,
    /// mais s'il affiche des chiffres, ils valent zéro.
    @Test func expiredClampsToZero() {
        let countdown = WeeklyCountdown(remaining: -50)
        #expect(!countdown.showsDays)
        #expect(countdown.hours == 0)
        #expect(countdown.minutes == 0)
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/WeeklyCountdownTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'WeeklyCountdown'`).

- [ ] **Step 3 : l'implémentation**

```swift
// NeonCompass/Features/Social/WeeklyCountdown.swift
import SwiftUI

/// La décomposition du rebours compact du héro. Pur, donc testé : la vue ne
/// décide de rien.
///
/// Deux unités seulement — jours+heures, puis heures+minutes le dernier jour.
/// Le rebours à la seconde de `NCCountdownDigits` vit dans la fiche complète ;
/// ici on répond à « combien de temps il reste » d'un coup d'œil.
struct WeeklyCountdown: Equatable {
    let showsDays: Bool
    let days: Int
    let hours: Int
    let minutes: Int

    init(remaining: TimeInterval) {
        let total = max(0, Int(remaining))
        showsDays = total >= 86_400
        days = total / 86_400
        hours = showsDays ? (total % 86_400) / 3600 : total / 3600
        minutes = (total % 3600) / 60
    }
}

/// Le texte du rebours, localisé par le système (« 2j 14h », « 2d 14h ») —
/// aucune clé de catalogue, donc rien à traduire ni à couvrir.
struct WeeklyCountdownLabel: View {
    let remaining: TimeInterval

    var body: some View {
        let countdown = WeeklyCountdown(remaining: remaining)
        let allowed: Set<Duration.UnitsFormatStyle.Unit> =
            countdown.showsDays ? [.days, .hours] : [.hours, .minutes]
        Text(
            Duration.seconds(max(0, remaining))
                .formatted(.units(allowed: allowed, width: .narrow, maximumUnitCount: 2))
        )
        .font(NCTypography.cardTitle.monospacedDigit())
        .foregroundStyle(NCColor.neonCyan)
        .ncNeonGlow(NCColor.neonCyan)
        .lineLimit(1)
    }
}
```

- [ ] **Step 4 : vérifier le succès**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/WeeklyCountdownTests 2>&1 | grep -E "Test run|TEST"`
Expected : `Test run with 4 tests passed`, `TEST SUCCEEDED`.

- [ ] **Step 5 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/WeeklyCountdown.swift NeonCompassTests/Social/WeeklyCountdownTests.swift NeonCompass.xcodeproj
git commit -m "feat(social): rebours compact à deux unités pour le héro"
```

---

### Task 3: Extraire « ce qui vaut le coup » (`OnlineEventHighlights`)

**Files:**
- Create: `NeonCompass/Features/Social/OnlineEventHighlights.swift`
- Modify: `NeonCompass/Features/Social/OnlineEventCard.swift` (supprimer `Highlight`, `highlights`, `rank(_:)` privés ; consommer le type extrait)
- Test: `NeonCompassTests/Social/OnlineEventHighlightsTests.swift`

**Interfaces:**
- Consumes: `OnlineEvent`, `OnlineEventFormatting` (existants).
- Produces: `OnlineEventHighlight { icon: String, name: String, value: LocalizedStringKey }` (`Identifiable`) ; `OnlineEventHighlights.compute(for: OnlineEvent, languageCode: String) -> [OnlineEventHighlight]` ; `OnlineEventHighlights.hiddenCount(for: OnlineEvent, shown: Int) -> Int`. Consommé par la tâche 4 et par `OnlineEventCard`.

- [ ] **Step 1 : le test qui échoue** — fixtures dans le style d'`OnlineEventsModelTests` (JSON minimal décodé)

```swift
// NeonCompassTests/Social/OnlineEventHighlightsTests.swift
import Testing
import Foundation
@testable import NeonCompass

struct OnlineEventHighlightsTests {
    private func event(_ body: String) throws -> OnlineEvent {
        try JSONDecoder().decode(OnlineEvent.self, from: Data("""
        {
          "id": "online_test", "game": "gtav",
          "startsAt": "2026-08-13T09:00:00Z", "endsAt": "2026-08-20T09:00:00Z",
          "title": { "en": "t" }\(body.isEmpty ? "" : ",")
          \(body)
        }
        """.utf8))
    }

    /// « 3× » bat « +15 % » : une prime en pourcentage se compare ramenée à un
    /// facteur — la règle qui vivait en privé dans la carte.
    @Test func bestBonusComparesMultipliersAndPercents() throws {
        let event = try self.event("""
        "bonuses": [
          { "activity": { "en": "small" }, "percentBonus": 15, "includesRP": false },
          { "activity": { "en": "big" }, "multiplier": 3, "includesRP": false }
        ]
        """)
        let highlights = OnlineEventHighlights.compute(for: event, languageCode: "en")
        #expect(highlights.first?.name == "big")
    }

    @Test func bestDiscountIsTheLargestPercent() throws {
        let event = try self.event("""
        "discounts": [
          { "item": { "en": "cheap" }, "percent": 10 },
          { "item": { "en": "deep" }, "percent": 40 }
        ]
        """)
        let highlights = OnlineEventHighlights.compute(for: event, languageCode: "en")
        #expect(highlights.contains { $0.name == "deep" })
        #expect(!highlights.contains { $0.name == "cheap" })
    }

    @Test func emptyEventHasNoHighlights() throws {
        #expect(try OnlineEventHighlights.compute(for: event(""), languageCode: "en").isEmpty)
    }

    /// Le « +N » du héro : tout ce que la carte compacte ne montre pas —
    /// bonus + remises + récompenses + podium, moins ce qui est déjà affiché.
    @Test func hiddenCountCountsEverythingBeyondShown() throws {
        let event = try self.event("""
        "bonuses": [ { "activity": { "en": "a" }, "multiplier": 2, "includesRP": false } ],
        "discounts": [ { "item": { "en": "b" }, "percent": 30 }, { "item": { "en": "c" }, "percent": 10 } ],
        "rewards": [ { "kind": "vehicle", "item": { "en": "d" } } ],
        "podiumVehicle": { "en": "e" }
        """)
        // 1 bonus + 2 remises + 1 récompense + 1 podium = 5 entrées ; 2 affichées.
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 2) == 3)
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 5) == 0)
        #expect(OnlineEventHighlights.hiddenCount(for: event, shown: 9) == 0)
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/OnlineEventHighlightsTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'OnlineEventHighlights'`).

- [ ] **Step 3 : l'implémentation** — le code DÉMÉNAGE depuis `OnlineEventCard` (lignes 73-111 actuelles), il n'est pas réécrit

```swift
// NeonCompass/Features/Social/OnlineEventHighlights.swift
import SwiftUI

/// Une ligne « ce qui vaut le coup » : le meilleur bonus, la meilleure remise,
/// la première récompense. Extrait d'`OnlineEventCard` le jour où le héro
/// compact du hub a eu besoin des mêmes lignes — deux copies auraient divergé.
struct OnlineEventHighlight: Identifiable, Equatable {
    let icon: String
    let name: String
    let value: LocalizedStringKey
    var id: String { "\(icon)\(name)" }
}

enum OnlineEventHighlights {
    /// Calculé chez nous, jamais repris d'un « at a glance » de la source.
    static func compute(for event: OnlineEvent, languageCode: String) -> [OnlineEventHighlight] {
        var out: [OnlineEventHighlight] = []
        if let best = event.bonuses.max(by: { rank($0) < rank($1) }) {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.bonusesIcon,
                name: best.activity.resolved(for: languageCode),
                value: OnlineEventFormatting.label(for: best)
            ))
        }
        if let best = event.discounts.max(by: { $0.percent < $1.percent }) {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.discountsIcon,
                name: best.item.resolved(for: languageCode),
                value: "social.event.percentOff \(best.percent)"
            ))
        }
        if let first = event.rewards.first {
            out.append(OnlineEventHighlight(
                icon: OnlineEventFormatting.icon(for: first.kind),
                name: first.item.resolved(for: languageCode),
                value: LocalizedStringKey(first.kind.localizationKey)
            ))
        }
        return out
    }

    /// Une prime en pourcentage ne se compare pas à un multiple sur la même
    /// échelle : « +15 % » n'est pas meilleur que « 2× ». Ramenée à un facteur.
    static func rank(_ bonus: OnlineEventBonus) -> Double {
        if let multiplier = bonus.multiplier { return Double(multiplier) }
        if let percent = bonus.percentBonus { return 1 + Double(percent) / 100 }
        return 0
    }

    /// Ce que la carte compacte ne montre pas : toutes les entrées de la
    /// semaine, moins les `shown` déjà affichées. Alimente le « +N › » du héro.
    static func hiddenCount(for event: OnlineEvent, shown: Int) -> Int {
        let total = event.bonuses.count + event.discounts.count
            + event.rewards.count + (event.podiumVehicle != nil ? 1 : 0)
        return max(0, total - shown)
    }
}
```

Dans `OnlineEventCard.swift` : supprimer la struct privée `Highlight` (lignes 194-199), la propriété `highlights` (73-103) et `rank(_:)` (107-111) ; remplacer par

```swift
    private var highlights: [OnlineEventHighlight] {
        OnlineEventHighlights.compute(for: event, languageCode: languageCode)
    }
```

(le `ForEach(highlights)` et le reste du corps ne changent pas).

- [ ] **Step 4 : vérifier le succès + la non-régression de la carte**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/OnlineEventHighlightsTests -only-testing:NeonCompassTests/OnlineEventsModelTests 2>&1 | grep -E "Test run|TEST"`
Expected : les deux suites passent (`4 tests` + le compte existant d'`OnlineEventsModelTests`), `TEST SUCCEEDED`.

- [ ] **Step 5 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/OnlineEventHighlights.swift NeonCompass/Features/Social/OnlineEventCard.swift NeonCompassTests/Social/OnlineEventHighlightsTests.swift NeonCompass.xcodeproj
git commit -m "refactor(social): extraire les highlights de la carte pour le héro compact"
```

---

### Task 4: La carte héro compacte et la fiche de la semaine

**Files:**
- Create: `NeonCompass/Features/Social/WeeklyHeroCard.swift`
- Create: `NeonCompass/Features/Social/WeekDetailSheet.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (clé `social.hub.moreCount %lld`)

**Interfaces:**
- Consumes: `OnlineEventHighlights` (T3), `WeeklyCountdownLabel` (T2), `OnlineEventCard`, `NCTypography`, `NCColor`.
- Produces: `WeeklyHeroCard(event: OnlineEvent, now: Date, onOpenDetail: (() -> Void)? = nil)` — si `onOpenDetail` est nil, la carte présente elle-même `WeekDetailSheet` (compact) ; sinon elle appelle le callback (régulier, tâche 10). `WeekDetailSheet(event: OnlineEvent, now: Date)`.

- [ ] **Step 1 : la clé de catalogue** — script d'insertion (en-tête du plan) avec :

```python
insert("social.hub.moreCount %lld", {
    "en": "+%lld", "fr": "+%lld", "es": "+%lld", "it": "+%lld", "de": "+%lld"})
```

Vérifier : `git diff --stat NeonCompass/Resources/Localizable.xcstrings` → uniquement des ajouts.

- [ ] **Step 2 : les deux vues**

```swift
// NeonCompass/Features/Social/WeeklyHeroCard.swift
import SwiftUI

/// La semaine d'un jeu, en deux lignes : fenêtre + rebours, puis les deux
/// meilleures entrées. Toute la carte est une porte vers la fiche complète.
struct WeeklyHeroCard: View {
    let event: OnlineEvent
    let now: Date
    /// Posé par l'écran en largeur régulière pour ouvrir le panneau latéral ;
    /// nil en compact, où la carte présente sa propre feuille.
    var onOpenDetail: (() -> Void)? = nil

    @State private var showsDetail = false

    private var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        Button {
            if let onOpenDetail { onOpenDetail() } else { showsDetail = true }
        } label: {
            card
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) {
            WeekDetailSheet(event: event, now: now)
        }
    }

    private var card: some View {
        let highlights = Array(
            OnlineEventHighlights.compute(for: event, languageCode: languageCode).prefix(2)
        )
        let hidden = OnlineEventHighlights.hiddenCount(for: event, shown: highlights.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Chiffres romains nus (`shortLabel`), jamais la marque.
                Text(verbatim: event.game.shortLabel)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 7))
                Text(event.startsAt..<event.endsAt, format: .interval.day().month(.abbreviated))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 8)
                countdown
            }
            if !highlights.isEmpty {
                perksLine(highlights, hidden: hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Le seul accent lumineux de l'écran. Expiré : « terminé », jamais un
    /// rebours négatif.
    @ViewBuilder
    private var countdown: some View {
        if let remaining = event.remaining(at: now) {
            WeeklyCountdownLabel(remaining: remaining)
        } else {
            Text("social.event.over")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func perksLine(_ highlights: [OnlineEventHighlight], hidden: Int) -> some View {
        // En XXL la ligne passe à la ligne : rien ne se tronque, ça défile.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                if index > 0 {
                    Text(verbatim: "·")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text(highlight.value)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                Text(highlight.name)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if hidden > 0 {
                Spacer(minLength: 4)
                Text("social.hub.moreCount \(hidden)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
```

```swift
// NeonCompass/Features/Social/WeekDetailSheet.swift
import SwiftUI

/// La fiche complète de la semaine : l'`OnlineEventCard` d'avant, devenue le
/// détail du héro compact. Une feuille avec son propre `NavigationStack` —
/// aucun écran d'onglet n'a le sien.
struct WeekDetailSheet: View {
    let event: OnlineEvent
    let now: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    OnlineEventCard(event: event, now: now)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
            }
            .navigationTitle(Text(event.startsAt..<event.endsAt, format: .interval.day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
```

- [ ] **Step 3 : générer, compiler, couvrir la localisation**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | grep -E "Test run|TEST"`
Expected : `TEST SUCCEEDED` — la clé interpolée `social.hub.moreCount %lld` est atteignable et traduite ×5. (Ce build compile aussi les deux vues.)

- [ ] **Step 4 : commit**

```bash
git status --short   # le diff xcstrings doit se limiter à la clé ajoutée
git add NeonCompass/Features/Social/WeeklyHeroCard.swift NeonCompass/Features/Social/WeekDetailSheet.swift NeonCompass/Resources/Localizable.xcstrings NeonCompass.xcodeproj
git commit -m "feat(social): carte héro compacte et fiche de la semaine"
```

---

### Task 5: Le glissement entre jeux et l'épinglage du rebours

**Files:**
- Create: `NeonCompass/Features/Social/WeeklyHeroPager.swift`
- Create: `NeonCompass/Features/Social/HeroPinning.swift`
- Modify: `NeonCompass/Features/Social/OnlineEventsModel.swift` (variantes par-jeu)
- Test: `NeonCompassTests/Social/HeroPinningTests.swift`, ajouts dans `NeonCompassTests/Social/OnlineEventsModelTests.swift`

**Interfaces:**
- Consumes: `WeeklyHeroCard` (T4), `WeeklyCountdownLabel` (T2), `OnlineEventsModel`.
- Produces: `WeeklyHeroPager(model: OnlineEventsModel, now: Date, onOpenDetail: ((OnlineEvent) -> Void)? = nil)` ; `HeroPinning.isPinned(heroFrame: CGRect, visibleTop: CGFloat) -> Bool` ; `PinnedCountdownChip(game: Game, remaining: TimeInterval)` ; sur le modèle : `currentEvent(at: Date, game: Game) -> OnlineEvent?` et `latestEvent(game: Game) -> OnlineEvent?`.

- [ ] **Step 1 : les tests qui échouent**

Dans `OnlineEventsModelTests.swift`, ajouter :

```swift
    /// VI d'abord : `Game.allCases` commence par `leonida`, et `availableGames`
    /// suit cet ordre — le pager s'appuie dessus, ce test le fige.
    @Test func availableGamesListsLeonidaFirst() throws {
        let vi = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-13T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        let v = try event(id: "online_v", game: .reference, startsAt: "2026-08-13T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        #expect(OnlineEventsModel(events: [v, vi]).availableGames == [.leonida, .reference])
    }

    /// Les variantes par-jeu ne dépendent pas de `selectedGame` : chaque page du
    /// héro interroge SON jeu, quelle que soit la page affichée.
    @Test func perGameQueriesIgnoreSelectedGame() throws {
        let vi = try event(id: "online_vi", game: .leonida, startsAt: "2026-08-13T09:00:00Z", endsAt: "2026-08-20T09:00:00Z")
        let v = try event(id: "online_v", game: .reference, startsAt: "2026-08-06T09:00:00Z", endsAt: "2026-08-13T09:00:00Z")
        let model = OnlineEventsModel(events: [vi, v])
        model.selectedGame = .leonida
        #expect(model.currentEvent(at: date("2026-08-14T00:00:00Z"), game: .reference) == nil)
        #expect(model.latestEvent(game: .reference)?.id == "online_v")
        #expect(model.currentEvent(at: date("2026-08-14T00:00:00Z"), game: .leonida)?.id == "online_vi")
    }
```

Nouveau fichier `HeroPinningTests.swift` :

```swift
import Testing
import CoreGraphics
@testable import NeonCompass

struct HeroPinningTests {
    private let hero = CGRect(x: 0, y: 0, width: 320, height: 100)

    @Test func fullyVisibleHeroIsNotPinned() {
        #expect(!HeroPinning.isPinned(heroFrame: hero, visibleTop: 0))
    }

    /// La maquette : épinglé quand le héro est sorti à ~92 % (il en reste
    /// moins de 8 % sous le bord).
    @Test func almostGoneHeroIsPinned() {
        let frame = hero.offsetBy(dx: 0, dy: -95)   // il reste 5 pt visibles sur 100
        #expect(HeroPinning.isPinned(heroFrame: frame, visibleTop: 0))
    }

    @Test func halfVisibleHeroIsNotPinned() {
        let frame = hero.offsetBy(dx: 0, dy: -50)
        #expect(!HeroPinning.isPinned(heroFrame: frame, visibleTop: 0))
    }

    @Test func zeroHeightNeverPins() {
        #expect(!HeroPinning.isPinned(heroFrame: .zero, visibleTop: 0))
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/HeroPinningTests -only-testing:NeonCompassTests/OnlineEventsModelTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'HeroPinning'`, `currentEvent(at:game:)` inconnu).

- [ ] **Step 3 : l'implémentation**

Dans `OnlineEventsModel.swift`, ajouter les variantes et faire déléguer les existantes :

```swift
    /// L'événement actif d'un jeu donné — la version `selectedGame` délègue ici.
    func currentEvent(at now: Date, game: Game) -> OnlineEvent? {
        events
            .filter { $0.game == game && $0.isActive(at: now) }
            .max { isEarlier($0, than: $1) }
    }

    func currentEvent(at now: Date) -> OnlineEvent? {
        currentEvent(at: now, game: selectedGame)
    }

    func latestEvent(game: Game) -> OnlineEvent? {
        events.filter { $0.game == game }.max { lhs, rhs in
            if lhs.endsAt != rhs.endsAt { return lhs.endsAt < rhs.endsAt }
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.id < rhs.id
        }
    }

    func latestEvent() -> OnlineEvent? {
        latestEvent(game: selectedGame)
    }
```

(supprimer les corps dupliqués des deux fonctions historiques — elles ne font plus que déléguer).

```swift
// NeonCompass/Features/Social/HeroPinning.swift
import SwiftUI

/// Le seuil d'épinglage du rebours. Pur, donc testé ; la valeur se règle à
/// l'œil au simulateur — la spec part de « héro sorti à 92 % ».
enum HeroPinning {
    static let visibleFraction: CGFloat = 0.08

    static func isPinned(heroFrame: CGRect, visibleTop: CGFloat) -> Bool {
        guard heroFrame.height > 0 else { return false }
        let visible = heroFrame.maxY - visibleTop
        return visible < heroFrame.height * visibleFraction
    }
}

/// La capsule de rebours qui remplace le héro sorti de l'écran : le jeu de la
/// page active et le temps restant. « Le rebours est le produit », littéral.
struct PinnedCountdownChip: View {
    let game: Game
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: game.shortLabel)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.7))
            WeeklyCountdownLabel(remaining: remaining)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
```

```swift
// NeonCompass/Features/Social/WeeklyHeroPager.swift
import SwiftUI

/// Une carte par jeu pourvu d'événements, VI d'abord (l'ordre de
/// `availableGames`), glissement horizontal aligné page par page. Un seul jeu :
/// une seule carte, pas de points — la règle `showsGamePicker`, transposée.
struct WeeklyHeroPager: View {
    let model: OnlineEventsModel
    let now: Date
    var onOpenDetail: ((OnlineEvent) -> Void)? = nil

    @State private var pagedGame: Game?

    var body: some View {
        let games = model.availableGames
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(games) { game in
                        page(for: game)
                            .containerRelativeFrame(.horizontal)
                            .id(game)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $pagedGame)
            // La page visible EST la sélection : le reste de l'écran (bannière,
            // rappels) continue de raisonner sur `selectedGame`.
            .onChange(of: pagedGame) { _, game in
                if let game { model.selectedGame = game }
            }
            .onAppear { pagedGame = model.selectedGame }

            if games.count > 1 {
                dots(games)
            }
        }
    }

    @ViewBuilder
    private func page(for game: Game) -> some View {
        if let shown = model.currentEvent(at: now, game: game) ?? model.latestEvent(game: game) {
            WeeklyHeroCard(event: shown, now: now, onOpenDetail: onOpenDetail.map { open in { open(shown) } })
        }
    }

    private func dots(_ games: [Game]) -> some View {
        HStack(spacing: 6) {
            ForEach(games) { game in
                Circle()
                    .fill(game == pagedGame ? NCColor.neonCyan : .white.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4 : vérifier le succès**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/HeroPinningTests -only-testing:NeonCompassTests/OnlineEventsModelTests 2>&1 | grep -E "Test run|TEST"`
Expected : `HeroPinningTests` = 4 tests, `OnlineEventsModelTests` = compte existant + 2, `TEST SUCCEEDED`.

- [ ] **Step 5 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/WeeklyHeroPager.swift NeonCompass/Features/Social/HeroPinning.swift NeonCompass/Features/Social/OnlineEventsModel.swift NeonCompassTests/Social/HeroPinningTests.swift NeonCompassTests/Social/OnlineEventsModelTests.swift NeonCompass.xcodeproj
git commit -m "feat(social): héro paginé VI d'abord et logique d'épinglage du rebours"
```

---

### Task 6: Le module « À voter »

**Files:**
- Create: `NeonCompass/Features/Social/VoteModule.swift`
- Create: `NeonCompass/Features/Social/ProposalsSheet.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (clés `social.hub.vote.title`, `social.hub.seeAll`)
- Test: `NeonCompassTests/Social/VotePreviewTests.swift`

**Interfaces:**
- Consumes: `CommunityModel` (`visibleSpots`, `myVotes`, `vote(on:direction:)`, `report`, `block`), `ContributionSections`, `ContributionRow`, `SocialHubVisibility.unvotedCount` (T1), `ContributeHintSheet`, `.signInToContributeAlert(isPresented:)`, `AppModel.openMapToContribute()`.
- Produces: `VoteModule(communityModel: CommunityModel, onSeeAll: (() -> Void)? = nil)` — nil : le module présente `ProposalsSheet` lui-même ; sinon callback (régulier, T10). `ProposalsSheet(communityModel: CommunityModel)`. `VotePreview.spots(discover:top:limit:)`.

- [ ] **Step 1 : le test qui échoue**

```swift
// NeonCompassTests/Social/VotePreviewTests.swift
import Testing
@testable import NeonCompass

struct VotePreviewTests {
    /// « À découvrir » d'abord — l'ordre qui donne leur chance aux nouveaux
    /// spots — puis « les mieux notées » comblent jusqu'à trois.
    @Test func discoverComesFirstThenTopFills() {
        #expect(VotePreview.spots(discover: [1, 2], top: [3, 4]) == [1, 2, 3])
        #expect(VotePreview.spots(discover: [1, 2, 3, 4], top: [5]) == [1, 2, 3])
    }

    /// Tout voté : le module montre quand même les mieux notées plutôt que de
    /// disparaître — des propositions existent.
    @Test func emptyDiscoverFallsBackToTop() {
        #expect(VotePreview.spots(discover: [Int](), top: [7, 8]) == [7, 8])
    }

    @Test func emptyBothIsEmpty() {
        #expect(VotePreview.spots(discover: [Int](), top: []).isEmpty)
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/VotePreviewTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'VotePreview'`).

- [ ] **Step 3 : les clés** — script d'insertion avec :

```python
insert("social.hub.vote.title", {
    "en": "To vote", "fr": "À voter", "es": "Para votar",
    "it": "Da votare", "de": "Zum Abstimmen"})
insert("social.hub.seeAll", {
    "en": "All", "fr": "Tout", "es": "Todo", "it": "Tutto", "de": "Alle"})
```

- [ ] **Step 4 : l'implémentation**

```swift
// NeonCompass/Features/Social/VoteModule.swift
import SwiftUI

/// L'ordre du hub, réduit à une fonction pure pour être testé sans fixture.
enum VotePreview {
    static func spots<T>(discover: [T], top: [T], limit: Int = 3) -> [T] {
        Array((discover + top).prefix(limit))
    }
}

/// Le module primordial du hub : c'est lui qui alimente la carte VI en POI.
/// Trois propositions, vote inline sans naviguer, pastille locale, et la porte
/// « proposer » remontée — l'élan naît en votant.
struct VoteModule: View {
    @Environment(AuthModel.self) private var authModel
    @Environment(AppModel.self) private var appModel

    let communityModel: CommunityModel
    /// Posé par l'écran en largeur régulière (panneau latéral) ; nil en
    /// compact, où le module présente sa propre feuille.
    var onSeeAll: (() -> Void)? = nil

    @State private var showsAll = false
    @State private var showSignInToContribute = false
    @State private var showContributeHint = false

    var body: some View {
        let sections = ContributionSections(spots: communityModel.visibleSpots, myVotes: communityModel.myVotes)
        let preview = VotePreview.spots(discover: sections.discover, top: sections.top)
        let unvoted = SocialHubVisibility.unvotedCount(
            spotIDs: communityModel.visibleSpots.map(\.id),
            votedIDs: Set(communityModel.myVotes.keys)
        )

        VStack(alignment: .leading, spacing: 12) {
            header(unvoted: unvoted)
            ForEach(preview) { spot in
                ContributionRow(
                    spot: spot,
                    myVote: communityModel.myVotes[spot.id],
                    onVote: { direction in
                        guard authModel.userID != nil else {
                            showSignInToContribute = true
                            return
                        }
                        Task { await communityModel.vote(on: spot, direction: direction) }
                    },
                    onReport: { Task { await communityModel.report(spot, reason: nil) } },
                    onBlockAuthor: {
                        if let authorUid = spot.authorUid {
                            communityModel.block(authorUid: authorUid, handle: spot.authorHandle)
                        }
                    }
                )
            }
            if communityModel.contributionsEnabled {
                proposeRow
            }
        }
        .sheet(isPresented: $showsAll) { ProposalsSheet(communityModel: communityModel) }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
        .sheet(isPresented: $showContributeHint) {
            ContributeHintSheet(onOpenMap: { appModel.openMapToContribute() })
        }
    }

    private func header(unvoted: Int) -> some View {
        HStack(spacing: 8) {
            Text("social.hub.vote.title")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            if unvoted > 0 {
                // Le second accent cyan de l'écran, avec le rebours — et le
                // dernier : tout le reste du hub reste sobre.
                Text(unvoted, format: .number)
                    .font(.caption2.bold())
                    .foregroundStyle(NCColor.nightSky)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(NCColor.neonCyan, in: .capsule)
            }
            Spacer()
            Button {
                if let onSeeAll { onSeeAll() } else { showsAll = true }
            } label: {
                HStack(spacing: 3) {
                    Text("social.hub.seeAll")
                    Image(systemName: "chevron.right").font(.caption2.bold())
                }
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
            }
            .buttonStyle(.plain)
        }
    }

    /// La même porte que le volet d'avant, en une ligne : mêmes gardes
    /// (alerte si déconnecté, feuille d'explication sinon), même destination.
    private var proposeRow: some View {
        Button {
            guard authModel.userID != nil else {
                showSignInToContribute = true
                return
            }
            showContributeHint = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(NCColor.neonCyan)
                Text("social.proposals.contribute.title")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
```

```swift
// NeonCompass/Features/Social/ProposalsSheet.swift
import SwiftUI

/// La vue complète des propositions : l'actuel `ContributionsPanel`, rhabillé
/// en feuille avec son `NavigationStack` — sections « À découvrir » et « Les
/// mieux notées », bouton contribuer en bas, rien ne change dedans.
struct ProposalsSheet: View {
    let communityModel: CommunityModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    ContributionsPanel(communityModel: communityModel)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
            }
            .navigationTitle(Text("social.panel.proposals"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
```

- [ ] **Step 5 : vérifier le succès**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/VotePreviewTests -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | grep -E "Test run|TEST"`
Expected : `VotePreviewTests` = 3 tests, couverture ×5 verte, `TEST SUCCEEDED`.

- [ ] **Step 6 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/VoteModule.swift NeonCompass/Features/Social/ProposalsSheet.swift NeonCompassTests/Social/VotePreviewTests.swift NeonCompass/Resources/Localizable.xcstrings NeonCompass.xcodeproj
git commit -m "feat(social): module À voter — vote inline, pastille, porte proposer"
```

---

### Task 7: Le classement — tuile, podium, feuille

**Files:**
- Create: `NeonCompass/Features/Social/HubTile.swift`
- Create: `NeonCompass/Features/Social/LeaderboardTile.swift`
- Create: `NeonCompass/Features/Social/LeaderboardPodium.swift`
- Create: `NeonCompass/Features/Social/LeaderboardSheet.swift`
- Modify: `NeonCompass/Features/Social/LeaderboardSection.swift` (paramètre `startRank`)
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (3 clés)
- Test: `NeonCompassTests/Social/LeaderboardPodiumTests.swift`

**Interfaces:**
- Consumes: `LeaderboardRow` (`handle`, `approvedCount`), `LeaderboardSection`.
- Produces: `HubTile(titleKey:action:main:sub:)` (gabarit générique, réutilisé en H2) ; `LeaderboardTile(rows: [LeaderboardRow], myRank: Int?, onOpen: @escaping () -> Void)` ; `LeaderboardPodium.displayOrder(_ rows: [LeaderboardRow]) -> [LeaderboardRow]` ; `LeaderboardSheet(rows: [LeaderboardRow])` ; `LeaderboardSection(rows:startRank:)`.

- [ ] **Step 1 : le test qui échoue**

```swift
// NeonCompassTests/Social/LeaderboardPodiumTests.swift
import Testing
@testable import NeonCompass

struct LeaderboardPodiumTests {
    private func row(_ handle: String) -> LeaderboardRow {
        LeaderboardRow(uid: handle, handle: handle, xp: 0, approvedCount: 0)
    }

    /// L'ordre d'affichage d'un podium : 2ᵉ, 1ᵉʳ (au centre, surélevé), 3ᵉ.
    @Test func threeRowsRenderSecondFirstThird() {
        let order = LeaderboardPodium.displayOrder([row("a"), row("b"), row("c")])
        #expect(order.map(\.handle) == ["b", "a", "c"])
    }

    @Test func twoRowsRenderSecondThenFirst() {
        #expect(LeaderboardPodium.displayOrder([row("a"), row("b")]).map(\.handle) == ["b", "a"])
    }

    @Test func oneRowRendersAlone() {
        #expect(LeaderboardPodium.displayOrder([row("a")]).map(\.handle) == ["a"])
    }

    /// Au-delà de trois, le podium n'affiche que le trio de tête.
    @Test func extraRowsAreIgnored() {
        let order = LeaderboardPodium.displayOrder([row("a"), row("b"), row("c"), row("d")])
        #expect(order.count == 3)
        #expect(!order.map(\.handle).contains("d"))
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/LeaderboardPodiumTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'LeaderboardPodium'`).

- [ ] **Step 3 : les clés** — script d'insertion avec :

```python
insert("social.hub.leaderboard.leader %@", {
    "en": "%@ leads", "fr": "%@ en tête", "es": "%@ lidera",
    "it": "%@ in testa", "de": "%@ führt"})
insert("social.hub.leaderboard.myRank %lld", {
    "en": "My rank: %lld", "fr": "Mon rang : %lld", "es": "Mi puesto: %lld",
    "it": "La mia posizione: %lld", "de": "Mein Rang: %lld"})
insert("social.hub.leaderboard.contributors %lld", {
    "en": "%lld contributors", "fr": "%lld contributeurs", "es": "%lld contribuidores",
    "it": "%lld contributori", "de": "%lld Beitragende"})
```

- [ ] **Step 4 : l'implémentation**

```swift
// NeonCompass/Features/Social/HubTile.swift
import SwiftUI

/// Le gabarit « tuile » du hub : demi-largeur, un titre en petites capitales,
/// une ligne vivante, une sous-ligne, un chevron. Toute la tuile est le bouton.
struct HubTile<Main: View, Sub: View>: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let main: Main
    @ViewBuilder let sub: Sub

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(titleKey)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.35))
                }
                main
                Spacer(minLength: 0)
                sub
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
```

```swift
// NeonCompass/Features/Social/LeaderboardTile.swift
import SwiftUI

/// Le classement, rétrogradé en tuile : le meneur et mon rang. Le podium et le
/// top 50 vivent dans la vue complète — il retrouvera de la place quand la
/// base de contributeurs le justifiera.
struct LeaderboardTile: View {
    let rows: [LeaderboardRow]
    let myRank: Int?
    let onOpen: () -> Void

    var body: some View {
        HubTile(titleKey: "social.leaderboard.title", action: onOpen) {
            if let leader = rows.first {
                Text("social.hub.leaderboard.leader \(leader.handle)")
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        } sub: {
            if let myRank {
                Text("social.hub.leaderboard.myRank \(myRank)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("social.hub.leaderboard.contributors \(rows.count)")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
```

```swift
// NeonCompass/Features/Social/LeaderboardPodium.swift
import SwiftUI

/// Le podium top 3 de la vue complète. Le moment « gloire » du classement —
/// il vit dans la feuille, pas au premier écran.
struct LeaderboardPodium: View {
    let rows: [LeaderboardRow]

    /// 2ᵉ, 1ᵉʳ, 3ᵉ — l'ordre spatial d'un podium. Pur, donc testé, y compris
    /// avec moins de trois lignes.
    static func displayOrder(_ rows: [LeaderboardRow]) -> [LeaderboardRow] {
        let top = Array(rows.prefix(3))
        switch top.count {
        case 3: return [top[1], top[0], top[2]]
        case 2: return [top[1], top[0]]
        default: return top
        }
    }

    var body: some View {
        let ordered = Self.displayOrder(rows)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(ordered) { row in
                let rank = (rows.firstIndex(of: row) ?? 0) + 1
                step(row: row, rank: rank)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func step(row: LeaderboardRow, rank: Int) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(rank == 1 ? 0.16 : 0.08))
                .frame(height: rank == 1 ? 84 : rank == 2 ? 62 : 48)
                .overlay(alignment: .top) {
                    // Le rang, jamais traduit : `verbatim`, comme les rangs de
                    // `LeaderboardSection`.
                    Text(verbatim: "\(rank)")
                        .font(NCTypography.cardTitle)
                        .foregroundStyle(rank == 1 ? NCColor.sunsetOrange : .white.opacity(0.4))
                        .padding(.top, 8)
                }
            Text(row.handle)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("social.leaderboard.spots \(row.approvedCount)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}
```

```swift
// NeonCompass/Features/Social/LeaderboardSheet.swift
import SwiftUI

/// La vue complète du classement : podium, puis la liste à partir du 4ᵉ.
struct LeaderboardSheet: View {
    let rows: [LeaderboardRow]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        LeaderboardPodium(rows: rows)
                        if rows.count > 3 {
                            LeaderboardSection(rows: Array(rows.dropFirst(3)), startRank: 4)
                        }
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
            }
            .navigationTitle(Text("social.leaderboard.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

Dans `LeaderboardSection.swift` : ajouter le paramètre et l'utiliser dans le rang —

```swift
struct LeaderboardSection: View {
    let rows: [LeaderboardRow]
    /// La feuille numérote après le podium (4, 5, …) ; l'usage historique
    /// garde son défaut.
    var startRank: Int = 1
```

et remplacer `Text(verbatim: "\(index + 1)")` par `Text(verbatim: "\(startRank + index)")` (le commentaire existant sur `verbatim` reste).

- [ ] **Step 5 : vérifier le succès**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/LeaderboardPodiumTests -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | grep -E "Test run|TEST"`
Expected : `LeaderboardPodiumTests` = 4 tests, couverture verte, `TEST SUCCEEDED`.

- [ ] **Step 6 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/HubTile.swift NeonCompass/Features/Social/LeaderboardTile.swift NeonCompass/Features/Social/LeaderboardPodium.swift NeonCompass/Features/Social/LeaderboardSheet.swift NeonCompass/Features/Social/LeaderboardSection.swift NeonCompassTests/Social/LeaderboardPodiumTests.swift NeonCompass/Resources/Localizable.xcstrings NeonCompass.xcodeproj
git commit -m "feat(social): tuile Classement, podium et feuille top 50"
```

---

### Task 8: Le point sur l'onglet Social

**Files:**
- Create: `NeonCompass/Core/Online/WeekSeenStore.swift`
- Modify: `NeonCompass/App/AppModel.swift` (deux propriétés)
- Modify: `NeonCompass/App/CompactTabBar.swift` (le point)
- Modify: `NeonCompass/App/RootView.swift` (calcul au lancement + marquage à l'ouverture)
- Test: `NeonCompassTests/Social/SocialTabBadgeTests.swift`

**Interfaces:**
- Consumes: `ContentStore<OnlineEvent>` (motif `hydrateWidgetSummaryFromCache` de `RootView`), `OnlineEventsModel` (T5).
- Produces: `SocialTabBadge.showsDot(currentWeekID: String?, lastSeenID: String?) -> Bool` ; `WeekSeenStoring { lastSeenWeekID() -> String?, markWeekSeen(_ id: String) }` + `UserDefaultsWeekSeenStore` ; `AppModel.socialTabShowsDot: Bool`, `AppModel.socialCurrentWeekID: String?` ; `CompactTabBar(selection:showsSocialDot:)`.

Portée assumée (spec §Signaux) : le point vit dans `CompactTabBar` — la barre à
nous. En largeur régulière la `TabView` système n'en affiche pas, et c'est écrit.

- [ ] **Step 1 : le test qui échoue**

```swift
// NeonCompassTests/Social/SocialTabBadgeTests.swift
import Testing
@testable import NeonCompass

struct SocialTabBadgeTests {
    @Test func newWeekShowsTheDot() {
        #expect(SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: "online_w32"))
        #expect(SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: nil))
    }

    @Test func seenWeekHidesTheDot() {
        #expect(!SocialTabBadge.showsDot(currentWeekID: "online_w33", lastSeenID: "online_w33"))
    }

    /// Aucune semaine publiée : rien à signaler — un point qui mène à un état
    /// vide serait un mensonge.
    @Test func noWeekNeverShowsTheDot() {
        #expect(!SocialTabBadge.showsDot(currentWeekID: nil, lastSeenID: nil))
        #expect(!SocialTabBadge.showsDot(currentWeekID: nil, lastSeenID: "online_w32"))
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/SocialTabBadgeTests 2>&1 | tail -20`
Expected : échec de compilation (`cannot find 'SocialTabBadge'`).

- [ ] **Step 3 : l'implémentation**

```swift
// NeonCompass/Core/Online/WeekSeenStore.swift
import Foundation

/// « Une semaine pas encore vue » : l'identifiant de l'événement que le hub
/// montrerait, comparé au dernier marqué vu. Pur — la persistance est à côté.
enum SocialTabBadge {
    static func showsDot(currentWeekID: String?, lastSeenID: String?) -> Bool {
        guard let currentWeekID else { return false }
        return currentWeekID != lastSeenID
    }
}

/// La persistance du « vu ». Un protocole pour que les tests n'écrivent jamais
/// dans les vrais `UserDefaults`.
protocol WeekSeenStoring: Sendable {
    func lastSeenWeekID() -> String?
    func markWeekSeen(_ id: String)
}

struct UserDefaultsWeekSeenStore: WeekSeenStoring {
    private static let key = "socialLastSeenWeekID"

    func lastSeenWeekID() -> String? {
        UserDefaults.standard.string(forKey: Self.key)
    }

    func markWeekSeen(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.key)
    }
}
```

Dans `AppModel.swift`, ajouter (sous `showsSettings`) :

```swift
    /// Le point de nouveauté de l'onglet Social : une semaine synchronisée que
    /// l'utilisateur n'a pas encore vue. Calculé par `RootView` au lancement,
    /// éteint à l'ouverture de l'onglet.
    var socialTabShowsDot = false

    /// L'identifiant de la semaine que le hub montrerait — ce que l'ouverture
    /// de l'onglet marque comme vu.
    var socialCurrentWeekID: String?
```

Dans `CompactTabBar.swift` : ajouter `var showsSocialDot: Bool = false` sous le
binding, puis dans `tabButton(_:)` habiller l'icône :

```swift
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20))
                    .overlay(alignment: .topTrailing) {
                        if tab == .social && showsSocialDot {
                            // Magenta, comme le point de nouveauté du fil actu.
                            Circle()
                                .fill(NCColor.sunsetMagenta)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
```

Dans `RootView.swift` :

1. ajouter la constante (près de `leaderboardRepository`-style propriétés) :
```swift
    private let weekSeenStore: any WeekSeenStoring = UserDefaultsWeekSeenStore()
```
2. dans `compactLayout`, passer le drapeau :
```swift
            CompactTabBar(selection: $model.selectedTab, showsSocialDot: model.socialTabShowsDot)
```
3. dans le `.task` principal, **après** `await ContentSourceConfigurator.configureFromAppConfig()` :
```swift
            refreshSocialTabBadge()
```
4. la fonction (même motif que `hydrateWidgetSummaryFromCache` : lire le cache,
   sans attendre le réseau) :
```swift
    /// Le point de l'onglet Social, depuis le CACHE de contenu — même motif que
    /// `hydrateWidgetSummaryFromCache` : l'onglet Social n'est construit qu'à sa
    /// première visite, donc personne d'autre ne lirait cette collection avant.
    private func refreshSocialTabBadge() {
        let store = ContentStore<OnlineEvent>.live(
            collectionName: "online_events",
            modelContext: modelContext
        )
        let events = OnlineEventsModel(events: store.items)
        let shown = events.currentEvent(at: Date()) ?? events.latestEvent()
        model.socialCurrentWeekID = shown?.id
        model.socialTabShowsDot = SocialTabBadge.showsDot(
            currentWeekID: shown?.id,
            lastSeenID: weekSeenStore.lastSeenWeekID()
        )
    }
```
5. le marquage à l'ouverture de l'onglet — sur le `onChange` existant de
   `compactLayout` (qui alimente `builtTabs`), ajouter :
```swift
        .onChange(of: model.selectedTab, initial: true) { _, tab in
            builtTabs.insert(tab)
            if tab == .social, let id = model.socialCurrentWeekID {
                weekSeenStore.markWeekSeen(id)
                model.socialTabShowsDot = false
            }
        }
```

- [ ] **Step 4 : vérifier le succès**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/SocialTabBadgeTests 2>&1 | grep -E "Test run|TEST"`
Expected : `Test run with 3 tests passed`, `TEST SUCCEEDED`.

- [ ] **Step 5 : commit**

```bash
git status --short
git add NeonCompass/Core/Online/WeekSeenStore.swift NeonCompass/App/AppModel.swift NeonCompass/App/CompactTabBar.swift NeonCompass/App/RootView.swift NeonCompassTests/Social/SocialTabBadgeTests.swift NeonCompass.xcodeproj
git commit -m "feat(social): point de nouvelle semaine sur l'onglet"
```

---

### Task 9: La recomposition de `SocialScreen` (compact)

**Files:**
- Modify: `NeonCompass/Features/Social/SocialScreen.swift` (récrit — le corps complet est ci-dessous)
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (clé `social.hub.thisWeek`)

**Interfaces:**
- Consumes: tout ce qui précède — `WeeklyHeroPager`, `HeroPinning`, `PinnedCountdownChip`, `VoteModule`, `LeaderboardTile`, `LeaderboardSheet`, `SocialHubVisibility` ; plus l'existant : `OnlineEventsModel`, `CommunityModel.live`, `SupabaseLeaderboardRepository`, `EventReminderScheduler`, `SystemLocalNotificationScheduler`, `ProfileModel.profile?.rank`, `NCLayout.compactTabBarClearance`.
- Produces: le `SocialScreen` hub, monté tel quel par `RootView.screen(for:)`.

Disparaissent : `import Combine`, la minuterie `tick`, l'énumération `Panel`,
`availablePanels`, le `Picker` segmenté, `communityHubEnabled` et sa lecture
`app_config` (H1 n'a pas de section communautés ; `CommunitiesPanel` reste dans
le dépôt pour H2). `CommunitiesModel` n'est plus référencé par l'écran.

- [ ] **Step 1 : la clé** — script d'insertion avec :

```python
insert("social.hub.thisWeek", {
    "en": "This week", "fr": "Cette semaine", "es": "Esta semana",
    "it": "Questa settimana", "de": "Diese Woche"})
```

- [ ] **Step 2 : récrire l'écran**

```swift
// NeonCompass/Features/Social/SocialScreen.swift
import SwiftUI
import SwiftData

/// L'onglet Social, en hub : héro « Cette semaine » paginé par jeu (VI
/// d'abord), module « À voter », tuile Classement, bannière en queue. Une
/// section sans contenu disparaît — la règle `showsGamePicker`, généralisée.
/// Lisible sans compte : le compte n'est demandé que pour voter ou figurer au
/// classement, jamais pour lire.
struct SocialScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(AuthModel.self) private var authModel
    @Environment(ProfileModel.self) private var profileModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var model: OnlineEventsModel?
    @State private var leaderboardRows: [LeaderboardRow] = []
    @State private var communityModel: CommunityModel?
    @State private var heroPinned = false
    @State private var showsLeaderboard = false

    private let leaderboardRepository: any LeaderboardRepository = SupabaseLeaderboardRepository()
    private let notifications: any LocalNotificationScheduling = SystemLocalNotificationScheduler()

    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        // La tâche appartient à l'ÉCRAN, jamais au ProgressView : accrochée au
        // ProgressView elle s'annulerait elle-même dès que `model` est assigné.
        // Cf. FeedScreen, où ce défaut avait gardé le fil vide.
        .task { await loadModel() }
    }

    private func content(_ model: OnlineEventsModel) -> some View {
        // `.everyMinute` remplace la minuterie Combine d'avant : la sélection de
        // la semaine courante bascule à la minute, le rebours à la seconde vit
        // dans `NCCountdownDigits` (fiche) et le compact se contente du même pas.
        TimelineView(.everyMinute) { context in
            let now = context.date
            let shown = shownEvent(model, at: now)
            let visibility = SocialHubVisibility(
                serverEnabled: serverFeatures.isEnabled,
                proposalCount: communityModel?.visibleSpots.count ?? 0,
                leaderboardRowCount: leaderboardRows.count,
                heroShowsEvent: shown != nil,
                isProEntitled: proEntitlementModel.isProEntitled
            )

            ScrollView {
                VStack(spacing: 20) {
                    heroSection(model, now: now)
                    if visibility.showsVoteModule, let communityModel {
                        VoteModule(communityModel: communityModel)
                    }
                    // Tuile orpheline en H1 : elle s'étire en pleine largeur.
                    // La grille à deux colonnes arrive avec la seconde tuile (H2).
                    if visibility.showsLeaderboardTile {
                        LeaderboardTile(
                            rows: leaderboardRows,
                            myRank: profileModel.profile?.rank,
                            onOpen: { showsLeaderboard = true }
                        )
                    }
                    // Écran de liste : la bannière s'y applique (spec §5), en
                    // queue de colonne, jamais sur un état vide.
                    if visibility.showsBanner {
                        BannerAdView()
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(20)
                // La barre d'onglets flotte au-dessus du contenu — même réserve
                // que le fil actu, que l'écran d'avant n'avait pas besoin de
                // poser parce qu'il était court.
                .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
            }
            .refreshable {
                await model.refresh()
                // Sans ça, une date de fin corrigée côté contenu ne bougerait le
                // rappel qu'au prochain lancement à froid.
                await scheduleReminders(for: model.events)
                await loadLeaderboard()
                await loadCommunity()
            }
            .overlay(alignment: .top) {
                if heroPinned, let shown, let remaining = shown.remaining(at: now) {
                    PinnedCountdownChip(game: shown.game, remaining: remaining)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .sheet(isPresented: $showsLeaderboard) {
                LeaderboardSheet(rows: leaderboardRows)
            }
        }
    }

    /// Ce que le héro montre pour le jeu sélectionné — la fenêtre active, sinon
    /// la dernière terminée (dite « terminé », jamais en cours).
    private func shownEvent(_ model: OnlineEventsModel, at now: Date) -> OnlineEvent? {
        model.currentEvent(at: now) ?? model.latestEvent()
    }

    @ViewBuilder
    private func heroSection(_ model: OnlineEventsModel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("social.hub.thisWeek")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            if model.availableGames.isEmpty {
                emptyState
            } else {
                WeeklyHeroPager(model: model, now: now)
                    // Le frame du héro dans l'espace du scroll pilote
                    // l'épinglage ; le seuil est pur et testé (`HeroPinning`).
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .scrollView)
                    } action: { frame in
                        let pinned = HeroPinning.isPinned(heroFrame: frame, visibleTop: 0)
                        if pinned != heroPinned {
                            // Animer la COMMANDE, jamais la liste.
                            withAnimation(.easeInOut(duration: 0.2)) { heroPinned = pinned }
                        }
                    }
            }
        }
    }

    /// Rien de publié : on le dit, on n'invente pas une semaine.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("social.empty.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
            Text("social.empty.body")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func loadModel() async {
        guard model == nil else { return }
        let contentStore = ContentStore<OnlineEvent>.live(
            collectionName: "online_events",
            modelContext: modelContext
        )
        model = OnlineEventsModel(events: contentStore.items, contentStore: contentStore)
        try? await contentStore.syncIfNeeded()
        model?.update(events: contentStore.items)
        await scheduleReminders(for: contentStore.items)
        await loadLeaderboard()
        // Le module « À voter » est en première vue : son modèle se charge à
        // l'ouverture de l'écran, plus à la bascule d'un volet qui n'existe plus.
        await loadCommunity()
    }

    /// Garde du drapeau serveur : sans lui, ni vote ni classement — et pas de
    /// section vide non plus.
    private func loadCommunity() async {
        guard serverFeatures.isEnabled else { return }
        if communityModel == nil {
            communityModel = CommunityModel.live(modelContext: modelContext)
        }
        await communityModel?.loadApprovedSpots()
        if let uid = authModel.userID {
            await communityModel?.loadMyVotes(uid: uid)
        }
    }

    /// L'échec laisse la liste vide, et la tuile disparaît — état honnête,
    /// jamais un écran en erreur.
    private func loadLeaderboard() async {
        guard serverFeatures.isEnabled else { return }
        leaderboardRows = (try? await leaderboardRepository.fetchWeekly())?.rows ?? []
    }

    /// Reprogrammé à chaque synchronisation : un événement corrigé côté contenu
    /// doit déplacer son rappel, pas en ajouter un second. L'identifiant étant
    /// celui de l'événement, la reprogrammation remplace.
    private func scheduleReminders(for events: [OnlineEvent]) async {
        let pending = EventReminderScheduler.reminders(for: events, at: Date())
        guard !pending.isEmpty else { return }
        guard await notifications.requestPermissionIfNeeded() else { return }
        for reminder in pending {
            await notifications.schedule(
                id: reminder.id,
                title: String(localized: "social.reminder.title"),
                body: String(localized: "social.reminder.body"),
                at: reminder.fireAt
            )
        }
    }
}
```

- [ ] **Step 3 : compiler et lancer les suites Social + localisation**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:NeonCompassTests/OnlineEventsModelTests -only-testing:NeonCompassTests/SocialHubVisibilityTests -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | grep -E "Test run|TEST"`
Expected : trois suites vertes, `TEST SUCCEEDED`. En cas de réécriture parasite du catalogue par l'extraction : `git checkout -- NeonCompass/Resources/Localizable.xcstrings` puis réappliquer l'insertion de l'étape 1.

- [ ] **Step 4 : regarder l'écran** — les deux derniers défauts d'UI de cet onglet n'ont été vus qu'au simulateur

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/NeonCompass-*/Build/Products/Debug-iphonesimulator/NeonCompass.app | head -1)
BUNDLE_ID=$(defaults read "$APP/Info" CFBundleIdentifier)
xcrun simctl install booted "$APP" && xcrun simctl launch booted "$BUNDLE_ID"
sleep 4 && xcrun simctl io booted screenshot /tmp/social-hub-h1-iphone.png
```

Contrôler sur la capture : plus de segments ; en-tête « Cette semaine » + carte compacte ; drapeaux fermés = héro seul (+ bannière si événement) ; défilement → la capsule de rebours apparaît en haut ; retour en haut → elle disparaît.

- [ ] **Step 5 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/SocialScreen.swift NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(social): l'onglet devient le hub — les volets disparaissent"
```

---

### Task 10: La largeur régulière — mosaïque et panneau latéral

**Files:**
- Create: `NeonCompass/Features/Social/HubSidePanel.swift`
- Modify: `NeonCompass/Features/Social/SocialScreen.swift` (disposition régulière + hissage des présentations)

**Interfaces:**
- Consumes: `WeeklyHeroPager.onOpenDetail`, `VoteModule.onSeeAll`, `LeaderboardTile.onOpen`, `OnlineEventCard`, `ContributionsPanel`, `LeaderboardPodium`/`LeaderboardSection`.
- Produces: `HubSidePanel(titleKey:onClose:content:)` ; `SocialScreen.HubDetail` (enum interne `.week(OnlineEvent)`, `.proposals`, `.leaderboard`).

- [ ] **Step 1 : le panneau**

```swift
// NeonCompass/Features/Social/HubSidePanel.swift
import SwiftUI

/// Le panneau latéral des vues complètes en largeur régulière — à la place
/// d'une feuille, la règle du projet pour l'iPad posé à côté de la télé.
struct HubSidePanel<Content: View>: View {
    let titleKey: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(titleKey)
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("social.event.detail.close"))
            }
            .padding(20)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
            ScrollView {
                content
                    .padding(20)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(NCColor.nightSky.opacity(0.96))
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
        }
        // Ombre bornée — la leçon « écran noir, app vivante ».
        .shadow(color: .black.opacity(0.3), radius: 18, x: -8, y: 0)
        .transition(.move(edge: .trailing))
    }
}
```

- [ ] **Step 2 : hisser les présentations dans `SocialScreen`**

Ajouter à l'écran :

```swift
    /// Une vue complète ouverte. En compact chaque composant présente sa
    /// feuille ; en régulier l'écran centralise pour servir le panneau.
    private enum HubDetail: Identifiable {
        case week(OnlineEvent)
        case proposals
        case leaderboard

        var id: String {
            switch self {
            case .week(let event): "week-\(event.id)"
            case .proposals: "proposals"
            case .leaderboard: "leaderboard"
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .week: "social.hub.thisWeek"
            case .proposals: "social.panel.proposals"
            case .leaderboard: "social.leaderboard.title"
            }
        }
    }

    @State private var openedDetail: HubDetail?
    private var isRegular: Bool { sizeClass == .regular }

    private func openDetail(_ detail: HubDetail) {
        if isRegular {
            // Animer la commande, jamais la liste.
            withAnimation(.snappy) { openedDetail = detail }
        } else {
            switch detail {
            case .leaderboard: showsLeaderboard = true
            case .week, .proposals: break   // les composants présentent leur feuille
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: HubDetail, now: Date) -> some View {
        switch detail {
        case .week(let event):
            OnlineEventCard(event: event, now: now)
        case .proposals:
            if let communityModel {
                ContributionsPanel(communityModel: communityModel)
            }
        case .leaderboard:
            VStack(spacing: 20) {
                LeaderboardPodium(rows: leaderboardRows)
                if leaderboardRows.count > 3 {
                    LeaderboardSection(rows: Array(leaderboardRows.dropFirst(3)), startRank: 4)
                }
            }
        }
    }
```

Puis, dans `content(_:)`, envelopper le `ScrollView` existant dans un `HStack`
et brancher les callbacks **seulement en régulier** :

```swift
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        heroSection(model, now: now)   // inchangé
                        if visibility.showsVoteModule, let communityModel {
                            if isRegular {
                                // Mosaïque : le vote à gauche, la tuile à droite.
                                HStack(alignment: .top, spacing: 20) {
                                    VoteModule(communityModel: communityModel, onSeeAll: { openDetail(.proposals) })
                                    if visibility.showsLeaderboardTile {
                                        LeaderboardTile(
                                            rows: leaderboardRows,
                                            myRank: profileModel.profile?.rank,
                                            onOpen: { openDetail(.leaderboard) }
                                        )
                                        .frame(maxWidth: 280)
                                    }
                                }
                            } else {
                                VoteModule(communityModel: communityModel)
                            }
                        }
                        if !isRegular || !visibility.showsVoteModule {
                            if visibility.showsLeaderboardTile {
                                LeaderboardTile(
                                    rows: leaderboardRows,
                                    myRank: profileModel.profile?.rank,
                                    onOpen: { openDetail(.leaderboard) }
                                )
                            }
                        }
                        if visibility.showsBanner {
                            BannerAdView()
                        }
                    }
                    .frame(maxWidth: isRegular ? 900 : 640)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .padding(.bottom, sizeClass == .compact ? NCLayout.compactTabBarClearance : 16)
                }
                .refreshable { /* inchangé */ }
                .overlay(alignment: .top) { /* capsule, inchangé */ }
                .sheet(isPresented: $showsLeaderboard) {
                    LeaderboardSheet(rows: leaderboardRows)
                }

                if isRegular, let openedDetail {
                    HubSidePanel(
                        titleKey: openedDetail.titleKey,
                        onClose: { withAnimation(.snappy) { self.openedDetail = nil } }
                    ) {
                        detailContent(openedDetail, now: now)
                    }
                }
            }
```

Et le héro en régulier route la fiche vers le panneau :

```swift
                WeeklyHeroPager(
                    model: model,
                    now: now,
                    onOpenDetail: isRegular ? { event in openDetail(.week(event)) } : nil
                )
```

- [ ] **Step 3 : compiler et regarder l'iPad**

Run : `xcodegen generate && xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build`
Expected : `BUILD SUCCEEDED`.

```bash
xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null; open -a Simulator
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/NeonCompass-*/Build/Products/Debug-iphonesimulator/NeonCompass.app | head -1)
BUNDLE_ID=$(defaults read "$APP/Info" CFBundleIdentifier)
xcrun simctl install booted "$APP" && xcrun simctl launch booted "$BUNDLE_ID"
sleep 4 && xcrun simctl io booted screenshot /tmp/social-hub-h1-ipad.png
```

Contrôler : héro pleine largeur (≤ 900 pt) ; vote à gauche, tuile à droite ; « Tout › » ouvre le panneau à droite (pas une feuille) ; la croix le referme ; la fiche de la semaine s'ouvre dans le panneau depuis la carte héro.

- [ ] **Step 4 : commit**

```bash
git status --short
git add NeonCompass/Features/Social/HubSidePanel.swift NeonCompass/Features/Social/SocialScreen.swift NeonCompass.xcodeproj
git commit -m "feat(social): mosaïque iPad et panneau latéral pour les vues complètes"
```

---

### Task 11: Vérification finale

**Files:** aucun nouveau — c'est la passe de preuve.

- [ ] **Step 1 : la suite complète**

Run : `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "Test run|TEST|failed"`
Expected : `TEST SUCCEEDED`, aucun `failed`. Le compte total doit avoir augmenté de **28 tests** par rapport à `origin/main` (4 visibilité + 4 rebours + 4 highlights + 4 épinglage + 2 modèle + 3 aperçu du vote + 4 podium + 3 badge d'onglet).

- [ ] **Step 2 : le catalogue n'a pas été réécrit par l'extraction**

Run : `git status --short NeonCompass/Resources/Localizable.xcstrings`
Expected : rien (ou uniquement nos clés si un commit est en attente). Une variante `%@` apparue sans traduction = artefact de `xcodebuild test` → `git checkout -- NeonCompass/Resources/Localizable.xcstrings`.

- [ ] **Step 3 : la revue visuelle des deux appareils**

Sur les captures (`/tmp/social-hub-h1-iphone.png`, `/tmp/social-hub-h1-ipad.png`) et en manipulant :

- [ ] plus aucun sélecteur à segments nulle part ;
- [ ] héro : pastille du jeu en chiffres romains, fenêtre, rebours cyan — seul accent avec la pastille « À voter » ;
- [ ] glissement VI ⇄ V si les deux jeux ont du contenu (sinon : pas de points) ;
- [ ] défilement : capsule de rebours épinglée, avec le jeu de la page active ;
- [ ] tap sur le héro : fiche complète (l'ancienne carte), catégories et leurs feuilles fonctionnelles ;
- [ ] pastille = nombre de propositions non votées ; voter la fait décroître ;
- [ ] « Proposer un spot » : alerte si déconnecté, sinon feuille d'explication → carte VI ;
- [ ] tuile Classement pleine largeur (orpheline) ; tap → podium + liste numérotée à partir de 4 ;
- [ ] bannière en queue uniquement si un événement est affiché et sans Pro ;
- [ ] point magenta sur l'onglet Social au lancement avec une semaine non vue ; il s'éteint en ouvrant l'onglet et ne revient pas au relancement ;
- [ ] iPad : mosaïque + panneau latéral pour les trois vues complètes ;
- [ ] Dynamic Type XXL (Réglages du simulateur) : la ligne des bonus passe à la ligne, rien ne se tronque.

- [ ] **Step 4 : pousser et ouvrir la PR**

```bash
git push -u origin feat/social-hub-h1
gh pr create --title "Social en hub — palier H1" --body "$(cat <<'EOF'
Recompose l'onglet Social en hub à sections (spec 2026-08-14) : héro « Cette
semaine » compact et paginé VI d'abord, module « À voter » avec vote inline et
pastille, tuile Classement (podium en feuille), rebours épinglé, point de
nouvelle semaine sur l'onglet, mosaïque iPad avec panneau latéral. Les volets
et leur sélecteur à segments disparaissent ; aucun changement serveur.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Auto-relecture du plan (faite à l'écriture)

- **Couverture de la spec H1** : héro compact paginé VI d'abord (T4-T5), « +N › » (T3-T4), rebours auto sans Combine (T2, T9), épinglage (T5, T9), module À voter + pastille + porte proposer (T1, T6), tuile Classement + podium en feuille + mon rang (T7, T9), point d'onglet (T8), sections retirables (T1, T9), bannière (T1, T9), sheets avec `NavigationStack` (T4, T6, T7), iPad mosaïque + panneau (T10), localisation ×5 (T4, T6, T7, T9), tests listés par la spec (T1-T8), vérification à l'écran (T9-T11).
- **Écarts assumés, dits dans les tâches** : `Duration.formatted(.units)` au lieu de `Text(timerInterval:)` (T2) ; le point d'onglet en compact seulement (T8) ; en H1 la « grille » est une tuile orpheline pleine largeur — la grille à deux colonnes naît en H2 avec la seconde tuile (T9).
- **Cohérence des types** : `SocialHubVisibility.unvotedCount(spotIDs:votedIDs:)` identique en T1/T6 ; `currentEvent(at:game:)`/`latestEvent(game:)` identiques en T5/T8/T9 ; `onOpenDetail`/`onSeeAll`/`onOpen` optionnels posés en T4/T5/T6/T7 et consommés en T10.
