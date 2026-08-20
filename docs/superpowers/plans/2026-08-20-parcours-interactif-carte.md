# Parcours interactif sur la carte — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer la feuille statique `RoutePlannerSheet` par un mode parcours interactif sur la carte : caméra menée de point en point, coche qui marque « trouvé », saut, sortie libre.

**Architecture:** Une logique pure `RouteRun` (Core, testée), un panneau muet `RouteModePanel` (Features), un canal de rendu « cible de parcours » dans le moteur de carte (`MapScrollView`), et le câblage dans `MapScreen` qui détient l'état du mode. `RoutePlanner` (le glouton) est inchangé.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, Swift Testing, XcodeGen, String Catalog.

**Spec:** `docs/superpowers/specs/2026-08-19-parcours-interactif-carte-design.md` — lue avant toute décision ; ses six décisions tranchées ne se relitigent pas.

## Global Constraints

- Cible iOS/iPadOS 26+, Swift 6 strict concurrency, SwiftUI uniquement.
- Toute chaîne visible passe par le String Catalog (`NeonCompass/Resources/Localizable.xcstrings`), 5 langues : en (base + fallback), fr, es, it, de.
- **Catalogue : retouches chirurgicales UNIQUEMENT** (Edit sur le texte exact) — jamais de relecture/redump JSON du fichier entier.
- Liquid Glass pour le chrome (`.glassEffect()`), au plus trois accents lumineux par écran.
- Nouveaux tests en Swift Testing (`import Testing`), jamais XCTest.
- **`xcodegen generate` obligatoire après toute création ou suppression de fichier source** — sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- **`-only-testing` sur UN test ne lance rien et rapporte `TEST SUCCEEDED`** : toujours cibler la SUITE et lire la ligne `Test run with N tests` — un compte inattendu vaut échec.
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`** (variantes `%@` sans traduction) : vérifier `git status` avant chaque commit, restaurer par `git checkout -- NeonCompass/Resources/Localizable.xcstrings` si le fichier est modifié sans qu'on y ait touché volontairement.
- Simulateur : `iPhone 17` (iOS 26.5).
- Branche de travail : `carte/parcours-interactif` (la spec y est déjà commitée). Petits commits, un par tâche.
- Décisions de la spec qui contraignent chaque tâche : la coche appelle `MapModel.toggleFound(_:)` (qui BASCULE — toujours garder `if !model.isFound(poi)` avant l'appel) ; ordre figé à l'entrée, aucun recalcul ; périmètre = collectibles restants sur `model.pois` COMPLET, jamais `filteredPOIs` ; saut automatique des trouvés externes à l'avancement ; sortie libre, aucune persistance.

---

### Task 1 : `RouteRun` — logique pure du parcours

**Files:**
- Create: `NeonCompass/Core/Map/RouteRun.swift`
- Test: `NeonCompassTests/Map/RouteRunTests.swift`

**Interfaces:**
- Consumes: rien (aucune dépendance, pas même `POI` — la tournée porte des identifiants `String`).
- Produces: `struct RouteRun: Equatable, Sendable` avec `init(steps: [String])`, `let steps: [String]`, `private(set) var currentIndex: Int`, `var isFinished: Bool`, `var currentStepID: String?`, `var stepNumber: Int`, `var totalSteps: Int`, `mutating func advance(found: Set<String>)`. Les tâches 3 et 4 consomment exactement ces noms.

- [ ] **Step 1 : Écrire les tests (échec attendu)**

Créer `NeonCompassTests/Map/RouteRunTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct RouteRunTests {
    @Test func startsOnTheFirstStep() {
        let run = RouteRun(steps: ["a", "b", "c"])
        #expect(run.currentStepID == "a")
        #expect(run.stepNumber == 1)
        #expect(run.totalSteps == 3)
        #expect(!run.isFinished)
    }

    @Test func emptyRunIsFinishedImmediately() {
        let run = RouteRun(steps: [])
        #expect(run.isFinished)
        #expect(run.currentStepID == nil)
        #expect(run.totalSteps == 0)
    }

    @Test func advanceMovesToTheNextStep() {
        var run = RouteRun(steps: ["a", "b"])
        run.advance(found: [])
        #expect(run.currentStepID == "b")
        #expect(run.stepNumber == 2)
    }

    @Test func advancePastTheLastStepFinishes() {
        var run = RouteRun(steps: ["a"])
        run.advance(found: [])
        #expect(run.isFinished)
        #expect(run.currentStepID == nil)
    }

    @Test func advanceOnAFinishedRunStaysFinished() {
        var run = RouteRun(steps: [])
        run.advance(found: [])
        #expect(run.isFinished)
    }

    @Test func advanceSkipsAnExternallyFoundStep() {
        // « b » a été coché depuis sa fiche pendant le parcours : l'avancement
        // le saute sans état d'erreur (décision 5 de la spec).
        var run = RouteRun(steps: ["a", "b", "c"])
        run.advance(found: ["b"])
        #expect(run.currentStepID == "c")
        #expect(run.stepNumber == 3)
    }

    @Test func advanceSkipsConsecutiveExternallyFoundSteps() {
        var run = RouteRun(steps: ["a", "b", "c", "d"])
        run.advance(found: ["b", "c"])
        #expect(run.currentStepID == "d")
    }

    @Test func advanceFinishesWhenAllRemainingAreFound() {
        var run = RouteRun(steps: ["a", "b"])
        run.advance(found: ["b"])
        #expect(run.isFinished)
    }

    @Test func aSkippedStepIsNeverProposedAgain() {
        // « a » passé sans être trouvé : l'index n'avance que vers l'avant,
        // donc « a » ne revient jamais (décision 3 de la spec).
        var run = RouteRun(steps: ["a", "b", "c"])
        run.advance(found: [])
        #expect(run.currentStepID == "b")
        run.advance(found: [])
        #expect(run.currentStepID == "c")
        run.advance(found: [])
        #expect(run.isFinished)
    }
}
```

- [ ] **Step 2 : Vérifier que ça échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/RouteRunTests
```

Attendu : ÉCHEC de compilation, `cannot find 'RouteRun' in scope`. (Le `xcodegen generate` est indispensable : sans lui le fichier n'est pas dans le projet et le run rapporterait « 0 tests » en vert.)

- [ ] **Step 3 : Implémentation minimale**

Créer `NeonCompass/Core/Map/RouteRun.swift` :

```swift
import Foundation

/// L'état d'une tournée en cours : l'ordre des étapes, FIGÉ à l'entrée en mode
/// (pas de recalcul — un recalcul re-proposerait immédiatement un point passé,
/// qui reste le plus proche), et l'index courant. Logique pure, aucun import UI.
///
/// Les étapes sont des identifiants de POI et non des POI : le POI vivant
/// (position, titre, état trouvé) se relit chez son propriétaire au moment de
/// l'affichage — la tournée n'a pas de copie à laisser se périmer.
struct RouteRun: Equatable, Sendable {
    /// Identifiants de POI, dans l'ordre du glouton.
    let steps: [String]
    private(set) var currentIndex: Int

    init(steps: [String]) {
        self.steps = steps
        self.currentIndex = 0
    }

    var isFinished: Bool { currentIndex >= steps.count }
    var currentStepID: String? { isFinished ? nil : steps[currentIndex] }
    /// « Étape n/N » — n en base 1, plafonné à N pour l'état terminé.
    var stepNumber: Int { min(currentIndex + 1, steps.count) }
    var totalSteps: Int { steps.count }

    /// Avance d'AU MOINS un cran — validation et saut avancent pareil, un
    /// point passé n'est jamais re-proposé — puis saute les étapes déjà
    /// trouvées par un autre chemin (fiche POI, synchro d'un autre appareil).
    mutating func advance(found: Set<String>) {
        guard !isFinished else { return }
        repeat {
            currentIndex += 1
        } while !isFinished && found.contains(steps[currentIndex])
    }
}
```

- [ ] **Step 4 : Vérifier que ça passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/RouteRunTests
```

Attendu : PASS, et la ligne `Test run with 9 tests` — tout autre compte vaut échec.

- [ ] **Step 5 : Commit**

```sh
git add NeonCompass/Core/Map/RouteRun.swift NeonCompassTests/Map/RouteRunTests.swift
git commit -m "feat(carte): RouteRun, logique pure du parcours"
```

---

### Task 2 : Canal de rendu « cible de parcours » dans le moteur de carte

**Files:**
- Modify: `NeonCompass/Core/Map/MapScrollView.swift` (4 points d'édition, repérés par texte exact ci-dessous)

**Interfaces:**
- Consumes: `POIPinPalette.color(for:style:)`, `.symbol(for:)`, `.core(for:)` ; `MapGeometry.contentPoint(for:manifest:)` ; le paramètre existant `placement` comme modèle de plomberie.
- Produces: `struct MapRouteTarget: Equatable, Sendable { var position: NormalizedPoint; var category: POICategory }` et le paramètre `var routeTarget: MapRouteTarget? = nil` sur `TiledMapRepresentable` — c'est ce que la tâche 4 passe depuis `MapScreen`.

**Règle de la spec qui gouverne cette tâche :** la cible de parcours NE passe PAS par le canal `placement`. La présence du placement arme deux reconnaisseurs UIKit et éteint la frappe de tout le contenu (`.allowsHitTesting(placementPin == nil)`) ; la cible, elle, ne fait que dessiner — zoom, pan et fiches POI restent actifs pendant le mode. Ne toucher ni aux reconnaisseurs ni au `allowsHitTesting` existant.

- [ ] **Step 1 : Le type**

Dans `MapScrollView.swift`, juste APRÈS la fermeture de `struct MapPlacementPin` (chercher le texte exact ci-dessous), insérer le nouveau type :

Ancien texte (repère) :

```swift
struct MapPlacementPin: Equatable, Sendable {
    var position: NormalizedPoint
    var category: POICategory
}
```

Ajouter immédiatement après :

```swift
/// Le POI courant du mode parcours — position et catégorie, rien d'autre.
///
/// Un type distinct de `MapPlacementPin` malgré les mêmes champs : la présence
/// du placement ARME des reconnaisseurs et éteint la frappe du contenu, celle
/// de la cible de parcours ne fait que dessiner. Les confondre inviterait à
/// brancher l'un sur les effets de l'autre.
struct MapRouteTarget: Equatable, Sendable {
    var position: NormalizedPoint
    var category: POICategory
}
```

- [ ] **Step 2 : Le paramètre de `TiledMapRepresentable` et le jeton de contenu**

a) Dans `struct TiledMapRepresentable`, après la déclaration :

```swift
    /// Reçoit un point de CONTENU, comme `onLongPress` : la normalisation
    /// appartient à l'appelant, qui a déjà le manifeste sous la main.
    var onPlacementMoved: ((CGPoint) -> Void)?
```

ajouter :

```swift
    /// Le POI courant du mode parcours. Se DESSINE seulement — aucun geste,
    /// aucune extinction de frappe, contrairement à `placement`.
    var routeTarget: MapRouteTarget? = nil
```

(Valeur par défaut `nil` : le site d'appel de `MapScreen` n'est câblé qu'en tâche 4, le build reste vert entre-temps.)

b) Dans `struct ContentToken` (chercher `let placement: MapPlacementPin?` dans le jeton), après ce champ ajouter :

```swift
        /// La cible du parcours se DESSINE : sans elle ici, avancer d'une
        /// étape ne repousserait aucun contenu et l'anneau resterait cloué à
        /// la première. Même raison que `placement` juste au-dessus.
        let routeTarget: MapRouteTarget?
```

c) Dans la propriété calculée `contentToken`, après la ligne `placement: placement,` ajouter :

```swift
            routeTarget: routeTarget,
```

d) Dans `makeContent(zoom:coordinator:)`, après la ligne `placementPin: placement,` ajouter :

```swift
            routeTarget: routeTarget,
```

- [ ] **Step 3 : Le rendu dans `MapContentSwiftUIView`**

a) Après la déclaration `let placementPin: MapPlacementPin?` (dans `MapContentSwiftUIView`), ajouter :

```swift
    /// Le POI courant du mode parcours — dédié, par-dessus la carte, jamais
    /// via le pipeline de groupement : un cluster n'a pas de « point courant ».
    let routeTarget: MapRouteTarget?
```

b) Dans `body`, l'affichage. Ancien texte :

```swift
            if let placementPin {
                ghostPin(placementPin)
            }
        }
        .frame(width: fullSize, height: fullSize)
```

Nouveau texte :

```swift
            if let placementPin {
                ghostPin(placementPin)
            }
            if let routeTarget {
                routeTargetPin(routeTarget)
            }
        }
        .frame(width: fullSize, height: fullSize)
```

c) Juste après la fermeture de la fonction `ghostPin(_:)` (elle se termine par `.accessibilityHidden(true)` suivi de `}`), ajouter la pastille cible et son halo :

```swift
    /// Le POI courant du parcours. Même vocabulaire visuel que `ghostPin` —
    /// 44 pt, sujet de l'écran — mais anneau PLEIN (le point existe, rien
    /// n'est en train d'être posé) et halo pulsant dans la teinte de sa
    /// catégorie. Insensible aux gestes : le POI réel, en dessous, garde sa
    /// frappe — ouvrir sa fiche pendant le mode reste permis.
    private func routeTargetPin(_ target: MapRouteTarget) -> some View {
        let tint = POIPinPalette.color(for: target.category, style: style)
        return Image(systemName: POIPinPalette.symbol(for: target.category))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(POIPinPalette.core(for: style).opacity(0.9))
                    .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
                    .shadow(color: tint.opacity(0.7), radius: 6)
            )
            .background(RouteTargetHalo(tint: tint))
            .scaleEffect(pinScale)
            .position(MapGeometry.contentPoint(for: target.position, manifest: manifest))
            // L'avancement se SUIT des yeux : la pastille glisse vers l'étape
            // suivante pendant que la caméra s'y rend.
            .animation(.snappy(duration: 0.25), value: target.position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// L'anneau qui respire autour de la cible. Une vue à part pour porter le
    /// `@State` de la pulsation : `MapContentSwiftUIView` est reconstruite à
    /// chaque poussée de contenu, l'identité structurelle de cette sous-vue
    /// préserve l'animation en cours.
    private struct RouteTargetHalo: View {
        let tint: Color
        @State private var pulsing = false

        var body: some View {
            Circle()
                .stroke(tint.opacity(pulsing ? 0.0 : 0.6), lineWidth: 3)
                .scaleEffect(pulsing ? 1.9 : 1.0)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
        }
    }
```

- [ ] **Step 4 : Build**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Attendu : BUILD SUCCEEDED. (Aucun fichier créé ni supprimé : pas de xcodegen nécessaire ici.)

- [ ] **Step 5 : Commit**

```sh
git add NeonCompass/Core/Map/MapScrollView.swift
git commit -m "feat(carte): canal de rendu de la cible de parcours dans le moteur"
```

---

### Task 3 : Clés de localisation + panneau `RouteModePanel`

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (insertion chirurgicale, AVANT l'entrée `"map.routePlanner.empty"`)
- Create: `NeonCompass/Features/Map/RouteModePanel.swift`

**Interfaces:**
- Consumes: `RouteRun` (Task 1 : `isFinished`, `totalSteps`, `stepNumber`, lecture seule) ; `NCTypography.cardTitle/.cardMeta/.body`, `NCColor.neonCyan` ; clés réutilisées `map.routePlanner.title` et `map.routePlanner.empty`.
- Produces: `struct RouteModePanel: View` avec `init(run: RouteRun, currentTitle: String?, onValidate: @escaping () -> Void, onSkip: @escaping () -> Void, onExit: @escaping () -> Void)` (init membre par membre : `RouteModePanel(run:currentTitle:onValidate:onSkip:onExit:)`) — consommé par `MapScreen` en tâche 4. Cinq clés `map.routeMode.*` toutes traduites en 5 langues.

- [ ] **Step 1 : Les cinq clés, en une insertion**

Le catalogue trie ses clés : `map.routeMode.*` se range juste avant `map.routePlanner.empty` (M < P en ASCII). Faire UNE édition (Edit, texte exact) : remplacer la ligne

```
    "map.routePlanner.empty": {
```

par le bloc suivant (les cinq nouvelles entrées, puis la ligne d'origine) :

```json
    "map.routeMode.exit": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Beenden"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Exit"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Salir"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Quitter"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Esci"
          }
        }
      }
    },
    "map.routeMode.finished": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Tour abgeschlossen!"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Route complete!"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "¡Recorrido completado!"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Tournée terminée !"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Percorso completato!"
          }
        }
      }
    },
    "map.routeMode.skip": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Überspringen"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Skip"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Omitir"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Passer"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Salta"
          }
        }
      }
    },
    "map.routeMode.step %lld %lld": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Stopp %1$lld/%2$lld"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Stop %1$lld/%2$lld"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Parada %1$lld/%2$lld"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Étape %1$lld/%2$lld"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Tappa %1$lld/%2$lld"
          }
        }
      }
    },
    "map.routeMode.validate": {
      "localizations": {
        "de": {
          "stringUnit": {
            "state": "translated",
            "value": "Gefunden"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Found"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Encontrado"
          }
        },
        "fr": {
          "stringUnit": {
            "state": "translated",
            "value": "Trouvé"
          }
        },
        "it": {
          "stringUnit": {
            "state": "translated",
            "value": "Trovato"
          }
        }
      }
    },
    "map.routePlanner.empty": {
```

Vérification (lecture seule, jamais de redump) :

```sh
python3 -c "
import json
d = json.load(open('NeonCompass/Resources/Localizable.xcstrings'))
for k in ['map.routeMode.exit','map.routeMode.finished','map.routeMode.skip','map.routeMode.step %lld %lld','map.routeMode.validate']:
    locs = d['strings'][k]['localizations']
    assert sorted(locs) == ['de','en','es','fr','it'], (k, sorted(locs))
print('OK, 5 clés x 5 langues')
"
```

- [ ] **Step 2 : Le panneau**

Créer `NeonCompass/Features/Map/RouteModePanel.swift` :

```swift
import SwiftUI

/// Le panneau du mode parcours, muet : il affiche l'état de la tournée et
/// remonte trois gestes. Marquer trouvé, avancer, sortir — toute la logique
/// vit chez l'appelant, même partage des rôles que `ContributionPlacementPanel`.
///
/// Trois états, une seule surface : tournée vide (tout est déjà trouvé),
/// étape en cours, tournée terminée (l'appelant referme tout seul après ~1 s).
struct RouteModePanel: View {
    let run: RouteRun
    /// Titre du POI courant, résolu par l'appelant : le panneau ne connaît ni
    /// `MapModel` ni la langue. Nil quand la tournée est finie ou vide.
    let currentTitle: String?
    let onValidate: () -> Void
    let onSkip: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if run.totalSteps == 0 {
                empty
            } else if run.isFinished {
                finished
            } else {
                step
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("map.routePlanner.title")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
            Spacer()
            Button("map.routeMode.exit", systemImage: "xmark.circle.fill", action: onExit)
                .labelStyle(.iconOnly)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var empty: some View {
        Text("map.routePlanner.empty")
            .font(NCTypography.body)
            .foregroundStyle(.white.opacity(0.7))
    }

    private var finished: some View {
        Label("map.routeMode.finished", systemImage: "checkmark.seal.fill")
            .font(NCTypography.body)
            .foregroundStyle(NCColor.neonCyan)
    }

    @ViewBuilder
    private var step: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("map.routeMode.step \(run.stepNumber) \(run.totalSteps)")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
            // Verbatim : le titre arrive déjà résolu dans la langue de
            // l'utilisateur, le catalogue n'a rien à y faire.
            Text(verbatim: currentTitle ?? "")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
        }
        HStack(spacing: 12) {
            Button {
                onValidate()
            } label: {
                Label("map.routeMode.validate", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NCColor.neonCyan)

            Button("map.routeMode.skip", action: onSkip)
                .buttonStyle(.glass)
        }
    }
}
```

- [ ] **Step 3 : Build + couverture de localisation**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests
```

Attendu : BUILD + PASS, ligne `Test run with N tests` avec N > 0. Puis `git status` : si `Localizable.xcstrings` porte des variantes `%@` ajoutées par l'extraction, les retirer (`git diff` pour voir, puis retoucher chirurgicalement ou `git checkout --` si TOUT le diff est artefact — attention à ne pas jeter l'insertion du Step 1 : la vérifier au diff avant tout checkout).

- [ ] **Step 4 : Commit**

```sh
git add NeonCompass/Features/Map/RouteModePanel.swift NeonCompass/Resources/Localizable.xcstrings NeonCompass.xcodeproj/project.pbxproj
git commit -m "feat(carte): panneau du mode parcours et ses cinq clés"
```

---

### Task 4 : Câblage dans `MapScreen`, entrée par le bouton, suppression de la feuille

**Files:**
- Modify: `NeonCompass/Features/Map/MapScreen.swift` (7 points d'édition)
- Modify: `NeonCompass/Features/Map/MapFilterControls.swift` (2 points)
- Delete: `NeonCompass/Features/Map/RoutePlannerSheet.swift`
- Modify: `NeonCompass/Resources/Localizable.xcstrings` (suppression de `map.routePlanner.stepFormat`)

**Interfaces:**
- Consumes: `RouteRun` (Task 1), `MapRouteTarget` + paramètre `routeTarget` (Task 2), `RouteModePanel(run:currentTitle:onValidate:onSkip:onExit:)` (Task 3), `RoutePlanner.greedyRoute(from:)` (existant, inchangé), `MapModel.pois/.isFound(_:)/.toggleFound(_:)/.foundPOIIDs/.selection`, `MapFocusRequest(position:intent:)` avec `.place`, `MapScreen.currentLanguageCode()` (statique existante), `poi.title.resolved(for:)`.
- Produces: rien pour les tâches suivantes — c'est l'intégration terminale.

- [ ] **Step 1 : L'état du mode dans `MapScreen`**

Remplacer :

```swift
    @State private var showRoutePlanner = false
```

par :

```swift
    /// La tournée en cours — nil hors mode. Volontairement NON persistée : les
    /// validations vivent déjà dans la progression, la tournée n'a rien à elle.
    @State private var routeRun: RouteRun?
```

- [ ] **Step 2 : Le bouton d'entrée (`MapFilterControls`)**

a) Remplacer la déclaration :

```swift
    @Binding var showRoutePlanner: Bool
```

par :

```swift
    /// Entrée DIRECTE en mode parcours — plus de feuille intermédiaire.
    let onStartRoute: () -> Void
```

b) Remplacer le corps du bouton :

```swift
    private var routePlannerButton: some View {
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
```

par :

```swift
    private var routePlannerButton: some View {
        Button {
            onStartRoute()
        } label: {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("map.routePlanner.title"))
    }
```

c) Dans `MapScreen`, les DEUX sites d'appel (disposition compacte et régulière) : remplacer chaque occurrence de

```swift
                        showRoutePlanner: $showRoutePlanner
```

par :

```swift
                        onStartRoute: { startRoute(model: model) }
```

- [ ] **Step 3 : La fente de panneau, dans les deux dispositions**

a) Compacte — ancien texte :

```swift
                if placement != nil {
                    placementPanel
                        .padding(.bottom, 76)
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .bottom)
                        // Dégage la tab bar flottante, comme les contrôles
                        // d'affichage juste au-dessus.
                        .padding(.bottom, 76)
                }
            }
            .animation(.snappy, value: model.selection)
            .animation(.snappy, value: placement == nil)
```

Nouveau texte (le parcours prend la fente APRÈS la fiche : ouvrir une fiche
pendant le mode l'affiche par-dessus, la refermer rend le panneau du mode —
c'est ce qui garde les fiches POI vivantes pendant la tournée) :

```swift
                if placement != nil {
                    placementPanel
                        .padding(.bottom, 76)
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .bottom)
                        // Dégage la tab bar flottante, comme les contrôles
                        // d'affichage juste au-dessus.
                        .padding(.bottom, 76)
                } else if let run = routeRun {
                    routePanel(run, model: model)
                        .padding(.bottom, 76)
                }
            }
            .animation(.snappy, value: model.selection)
            .animation(.snappy, value: placement == nil)
            .animation(.snappy, value: routeRun)
```

b) Régulière — ancien texte :

```swift
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .trailing, width: 340)
                }
            }
            .animation(.snappy, value: placement == nil)
```

Nouveau texte :

```swift
                } else if let selection = model.selection {
                    detailPanel(selection, model: model, edge: .trailing, width: 340)
                } else if let run = routeRun {
                    routePanel(run, model: model)
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy, value: placement == nil)
            .animation(.snappy, value: routeRun)
```

- [ ] **Step 4 : La cible de parcours vers le moteur**

Au site d'appel de `TiledMapRepresentable`, après le bloc :

```swift
                onPlacementMoved: { canvasPoint in
                    placement?.position = MapGeometry.normalizedPoint(fromCanvasPoint: canvasPoint, manifest: manifest)
                },
```

insérer (l'ordre des arguments suit l'ordre de déclaration du struct — `routeTarget` est déclaré après `onPlacementMoved` en tâche 2) :

```swift
                // Dessinée par le moteur, par-dessus la carte — jamais via le
                // pipeline de groupement : un cluster n'a pas de « point
                // courant ». Nil dès que la tournée est finie ou quittée.
                routeTarget: currentRoutePOI(model: model).flatMap { poi in
                    poi.position.map { MapRouteTarget(position: $0, category: poi.category) }
                },
```

- [ ] **Step 5 : La logique du mode dans `MapScreen`**

Supprimer le bloc de la feuille :

```swift
        .sheet(isPresented: $showRoutePlanner) {
            RoutePlannerSheet(
                route: RoutePlanner.greedyRoute(
                    // Deliberately computed from the full, unfiltered `pois`
                    // array rather than `filteredPOIs` — the route planner
                    // must never be silently narrowed by the map's category
                    // chips or search text (see plan 6b-2 final-review fix).
                    from: model.pois.filter { $0.category == .collectible && $0.position != nil && !model.isFound($0) }
                ),
                languageCode: Self.currentLanguageCode()
            )
        }
```

Et ajouter, juste avant la fonction `loadMyContributionsIfNeeded()` (repère : son commentaire `/// Relit MES propositions`), la section du mode :

```swift
    // MARK: - Mode parcours

    /// Entre en mode : glouton calculé UNE fois — ordre figé, décision 3 de la
    /// spec — sur `pois` COMPLET, jamais `filteredPOIs` : les puces de
    /// catégorie et la recherche ne rétrécissent pas la tournée en silence
    /// (décision du plan 6b-2, revalidée par la spec).
    private func startRoute(model: MapModel) {
        guard routeRun == nil else { return }
        let remaining = model.pois.filter {
            $0.category == .collectible && $0.position != nil && !model.isFound($0)
        }
        routeRun = RouteRun(steps: RoutePlanner.greedyRoute(from: remaining).map(\.id))
        // La fente est partagée : une fiche restée ouverte cacherait le
        // panneau du mode qu'on vient de demander.
        model.selection = nil
        focusOnCurrentStep(model: model)
    }

    /// Le POI vivant de l'étape courante — relu à chaque évaluation plutôt que
    /// copié dans la tournée, pour que titre et état trouvé ne se périment pas.
    private func currentRoutePOI(model: MapModel) -> POI? {
        guard let id = routeRun?.currentStepID else { return nil }
        return model.pois.first { $0.id == id }
    }

    private func focusOnCurrentStep(model: MapModel) {
        guard let position = currentRoutePOI(model: model)?.position else { return }
        // `.place` et non `.reveal` : même cadrage que la pose d'épingle —
        // assez près pour viser, et le point dans le HAUT de l'écran, au-dessus
        // du panneau qui occupe le bas.
        focusRequest = MapFocusRequest(position: position, intent: .place)
    }

    private func validateRouteStep(model: MapModel) {
        // `toggleFound` BASCULE : sans cette garde, valider une étape déjà
        // cochée depuis sa fiche la DÉ-trouverait.
        if let poi = currentRoutePOI(model: model), !model.isFound(poi) {
            model.toggleFound(poi)
        }
        advanceRoute(model: model)
    }

    private func advanceRoute(model: MapModel) {
        routeRun?.advance(found: model.foundPOIIDs)
        if let run = routeRun, run.isFinished {
            // Tournée terminée : l'état se montre ~1 s, puis sortie
            // automatique. Comparé à la valeur capturée : si l'utilisateur a
            // quitté puis relancé une tournée pendant la seconde, on ne
            // referme pas la sienne.
            Task {
                try? await Task.sleep(for: .seconds(1))
                if routeRun == run { routeRun = nil }
            }
        } else {
            focusOnCurrentStep(model: model)
        }
    }

    @ViewBuilder
    private func routePanel(_ run: RouteRun, model: MapModel) -> some View {
        RouteModePanel(
            run: run,
            currentTitle: currentRoutePOI(model: model)?.title.resolved(for: Self.currentLanguageCode()),
            onValidate: { validateRouteStep(model: model) },
            onSkip: { advanceRoute(model: model) },
            onExit: { routeRun = nil }
        )
    }
```

- [ ] **Step 6 : Supprimer la feuille et sa clé**

a) Supprimer le fichier :

```sh
git rm NeonCompass/Features/Map/RoutePlannerSheet.swift
xcodegen generate
```

b) Retirer `map.routePlanner.stepFormat` du catalogue — retouche chirurgicale : repérer le bloc exact avec

```sh
grep -n -A 34 '"map.routePlanner.stepFormat"' NeonCompass/Resources/Localizable.xcstrings
```

puis UNE édition (Edit, texte exact) qui supprime tout le bloc, de la ligne `    "map.routePlanner.stepFormat": {` à son `},` fermant inclus (la clé suivante du fichier reste en place). Vérification en lecture seule :

```sh
python3 -c "
import json
d = json.load(open('NeonCompass/Resources/Localizable.xcstrings'))
assert 'map.routePlanner.stepFormat' not in d['strings']
assert 'map.routePlanner.title' in d['strings'] and 'map.routePlanner.empty' in d['strings']
print('OK, stepFormat retiré, title/empty conservés')
"
```

- [ ] **Step 7 : Build + suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : TEST SUCCEEDED, aucune régression. Puis `git status` : restaurer `Localizable.xcstrings` si l'extraction y a laissé des artefacts (`git diff` d'abord — ne pas jeter la suppression du Step 6).

- [ ] **Step 8 : Commit**

```sh
git add -A
git commit -m "feat(carte): mode parcours interactif, la feuille d'itinéraire disparaît"
```

---

### Task 5 : Vérification visuelle au simulateur (exécutée par le contrôleur, pas par un sous-agent)

Le compte Pro de test est déjà en place sur le simulateur (connecté + achat StoreKit test). Rappel `cliclick` : la barre de boutons de la carte et le panneau du mode n'habitent PAS un `ScrollView` — ils sont tapables ; recalibrer si la fenêtre du simulateur a bougé, et doubler chaque clic (le premier après `activate` peut ne produire qu'un survol).

- [ ] Installer et lancer le build sur `iPhone 17`, onglet Carte.
- [ ] Taper le bouton itinéraire → le mode s'ouvre : panneau « Étape 1/N », zoom réel sur le premier point, anneau pulsant sur le POI courant.
- [ ] « Trouvé » → le POI est coché (vérifier sur sa fiche ou l'anneau du Profil), la caméra file au point suivant, le compteur avance.
- [ ] « Passer » → avance sans cocher.
- [ ] Ouvrir la fiche d'un POI pendant le mode → elle s'affiche ; la refermer → le panneau du mode revient.
- [ ] « Quitter » → sortie immédiate, l'anneau disparaît.
- [ ] Rentrer à nouveau, dérouler jusqu'au bout → « Tournée terminée ! » ~1 s puis sortie automatique.
- [ ] Œil sur la fluidité pendant le halo pulsant : en cas de doute, compter les images perdues (méthode du dépôt), jamais chronométrer un appel SwiftUI.

---

## Auto-revue du plan (faite à l'écriture)

- **Couverture de la spec :** décisions 1 (coche = `toggleFound`, gardée) → T4 S5 ; 2 (mode direct, feuille supprimée) → T4 S2/S6 ; 3 (ordre figé) → T1 (`advance` seulement vers l'avant) + T4 S5 (glouton une fois) ; 4 (périmètre `pois` complet) → T4 S5 ; 5 (saut des trouvés externes) → T1 (`advance(found:)`) ; 6 (sortie libre, pas de persistance) → T3 (bouton X) + T4 (état `@State` non persisté). Cycle du mode (vide / actif / terminé ~1 s / sortie auto) → T3 (trois états du panneau) + T4 S5 (`advanceRoute`). Interface (panneau modèle placement, épingle dédiée hors clustering, caméra `MapFocusRequest`, carte interactive) → T2 + T3 + T4 S3/S4. Localisation (5 nouvelles clés ×5 langues, réutilisation title/empty, suppression stepFormat, retouches chirurgicales) → T3 S1 + T4 S6. Tests `RouteRunTests` (les 8 cas nommés par la spec, en 9 tests) → T1. Vérification simulateur → T5.
- **Placeholders :** aucun — chaque étape porte son code ou sa commande exacte.
- **Cohérence des types :** `RouteRun(steps:)`/`currentStepID`/`stepNumber`/`totalSteps`/`isFinished`/`advance(found:)` identiques en T1/T3/T4 ; `MapRouteTarget(position:category:)` identique en T2/T4 ; `RouteModePanel(run:currentTitle:onValidate:onSkip:onExit:)` identique en T3/T4 ; clés `map.routeMode.exit/.finished/.skip/.step %lld %lld/.validate` identiques en T3 S1/S2.
