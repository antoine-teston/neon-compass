# Fondu des bords et plafond de zoom par appareil — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le plafond de zoom devient une fonction de l'appareil (4,95 sur iPad, 3,3 inchangé sur iPhone), et les quatre bords de la carte s'éteignent en 80 points d'écran au lieu d'être une découpe franche.

**Architecture:** Deux fonctions pures dans `Core/Map/` — l'une rend le plafond, l'autre l'état du calque de fondu — et deux branchements dans le moteur qui n'ont pas d'arithmétique à eux. Le fondu est UN calque `CALayer` posé entre les tuiles et les épingles, avec une image de neuf tranches (`contentsCenter`) dont l'échelle suit le zoom : l'épaisseur reste constante à l'écran sans jamais regraver l'image ni redimensionner le calque.

**Tech Stack:** Swift 6 (concurrence stricte), UIKit sous `UIViewRepresentable` (`Core/Map/`), Core Graphics pour l'image, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-15-carte-fondu-et-plafond-design.md`

## Global Constraints

- **Worktree** : tout se fait dans `/Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond`, branche `feat/carte-fondu-plafond`. Ne jamais toucher `/Users/antoine/gta_project` — un autre travail y est en cours.
- **Tests** : Swift Testing (`import Testing`), jamais XCTest.
- **`-only-testing` sur UN test ne lance rien et rapporte `TEST SUCCEEDED`.** Toujours cibler la SUITE (`-only-testing:NeonCompassTests/MaSuite`) et lire la ligne `Test run with N tests` — un compte inattendu vaut échec.
- **`xcodebuild test` se fige APRÈS avoir imprimé `Test run with N tests`.** Le lancer en arrière-plan avec redirection dans un fichier, attendre l'apparition de la ligne, puis `pkill -f xcodebuild`. Ne JAMAIS lancer deux `xcodebuild` en même temps sur le même DerivedData.
- **`xcodegen generate`** après toute création ou suppression de fichier source, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- **`xcodebuild test` peut réécrire `NeonCompass/Resources/Localizable.xcstrings`.** Vérifier `git status` avant chaque commit et restaurer (`git checkout -- NeonCompass/Resources/Localizable.xcstrings`) plutôt que d'emporter l'artefact.
- **Ressources `type: folder`** (`MapArt/`, `MapTiles/`) : PAS recopiées quand leur contenu change. Avant toute vérification visuelle, effacer la destination — `BUILT_PRODUCTS_DIR` vient de `-showBuildSettings`, jamais d'un glob dans DerivedData.
- **Commits** : un hook rejette `git commit -m`. Écrire le message dans un fichier avec l'outil Write, puis `git commit -F <fichier>`. Terminer chaque message par `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **`git diff -- <chemin>` ne rend rien** à travers le proxy rtk : utiliser `/usr/bin/git --no-pager diff`.
- **Aucune chaîne visible par l'utilisateur n'est ajoutée par ce plan.** Si l'envie s'en présente, elle passe par le String Catalog — mais elle ne devrait pas se présenter.
- **Aucune marque Rockstar** nulle part dans le code ni les commentaires de ce plan.
- **Simulateurs** : `iPhone 17` = `BD68054B-7C1F-48C8-B792-AB2C87C4B7A3` (iOS 26.5, ×3) ; `iPad Pro 13-inch (M5)` = `BD8F6F17-90B0-42CD-BE05-10866A1BE21D` (×2). Identifiant de l'app : `co.antoineteston.NeonCompass`.
- **Automatisation du simulateur** : `xcrun simctl` uniquement. Ni `osascript`, ni AppleScript, ni « System Events », ni `screencapture` — l'écran du Mac est verrouillé et ces outils atteindraient le vrai bureau.
- **Petits diffs.** Une tâche = un ou deux commits. Pas de refactorisation opportuniste.

### Les deux tableaux qui font autorité

Le plafond, `plafond = côtéSource × tolérance ÷ (côtéContenu × displayScale)` avec `côtéContenu = 2 048` :

| carte | côté source | tolérance | iPhone ×3 | iPad ×2 |
|---|---|---|---|---|
| pyramidée | 18 432 | 1,10 | **3,30** | **4,95** |
| socle nu | 4 096 | 3,75 | **2,50** | **3,75** |

Les deux colonnes iPhone retombent EXACTEMENT sur les constantes d'aujourd'hui (3,3 et 2,5). C'est la propriété qui rend la formule vérifiable : elle n'introduit aucune valeur neuve, elle explique celles qu'on avait.

Le fondu : **80 points d'ÉCRAN**, sur l'image seule — les épingles restent nettes.

### Trois écarts assumés par rapport à la spec

À lire avant toute revue de conformité : ces trois points s'écartent de la LETTRE de la spec, chacun pour une raison qui n'était pas connue au moment de l'écrire. Aucun ne s'écarte de son intention.

1. **La spec dit « le plafond se recalcule dans `traitCollectionDidChange` ».** Ce point d'accroche est déprécié depuis iOS 17, et le projet vise iOS 26 sans chemin de repli. On passe donc par `registerForTraitChanges([UITraitDisplayScale.self], target:action:)`, qui est l'API vivante et qui a en prime l'avantage de ne se déclencher que sur le trait qui nous intéresse.

2. **La spec dit que le calque est « contre-échelonné : `transform = scale(1 / zoomScale)`, `bounds` = taille du contenu × `zoomScale` ».** On obtient exactement le même invariant — les unités du calque valent le point d'écran — en posant `contentsScale = displayScale × zoomScale` sur un calque de cadre FIXE. Une affectation de propriété par image au lieu d'un couple cadre + transformation, aucun calque de 10 000 pt de côté à faire vivre, et l'image se rééchantillonne au passage à la résolution exacte de l'appareil. La spec décrivait un mécanisme, pas une exigence ; l'exigence — « 80 pt d'écran à tous les zooms » — est tenue et testée.

3. **La spec dit « au repos, la carte remplit l'écran : le fondu est hors champ ». C'est faux, et le plan le corrige.** L'échelle de repos couvre l'écran sans bande vide, donc la carte affleure EXACTEMENT deux des quatre bords : sur iPad, 2 048 × 0,671875 = 1 376 pt pour une fenêtre de 1 376 pt. Un fondu toujours actif poserait donc une vignette de 80 pt en haut et en bas de l'écran au repos — précisément ce que la section « Ce qu'on ne fait pas » interdit (« Pas de fondu au repos »). D'où l'opacité qui suit la distance dont le bord le plus proche a quitté l'écran : nulle au repos, entière dès que les quatre bords ont pris la largeur de la bande d'avance. La spec avait raison sur la règle et tort sur le motif.

Deux fichiers dépassent aussi la portée annoncée par la spec (`MapScrollView`, `MapTileSet`, `MapGeometry`) : `MapEdgeFadeImage.swift` est créé — un générateur d'image bitmap n'a pas sa place dans un fichier de géométrie pure — et `NCColor.swift` gagne deux lignes pour exposer en composantes la couleur qu'il n'exposait qu'en `Color`.

---

### Task 1 : le plafond, en fonction pure

**Files:**
- Modify: `NeonCompass/Core/Map/MapTileSet.swift` (ajout en fin de l'`enum`, après `frame(for:contentSize:manifest:)` ligne 76)
- Test: `NeonCompassTests/Map/MapTileSetTests.swift` (ajout d'un fixture et d'une section)

**Interfaces:**
- Consomme : `MapTileManifest` (`levels: [Level]`, triés du plus grossier au plus fin ; `Level.side: Int`).
- Produit, pour la tâche 2 :
  - `MapTileSet.maximumZoomScale(contentSize: CGFloat, manifest: MapTileManifest?, displayScale: CGFloat) -> CGFloat`
  - `MapTileSet.pyramidUpscale: CGFloat`, `MapTileSet.baseUpscale: CGFloat`, `MapTileSet.unpyramidedBaseSide: CGFloat`

- [ ] **Step 1 : écrire le test qui échoue**

Ajouter dans `NeonCompassTests/Map/MapTileSetTests.swift`, juste après le fixture `manifest` existant (ligne 23), un second fixture :

```swift
    /// Celui-ci reprend au contraire les côtés RÉELLEMENT livrés — 9 216 et
    /// 18 432 — parce que les valeurs attendues du plafond sont ici les
    /// valeurs réelles, 3,3 et 4,95, et qu'un test du plafond écrit sur des
    /// puissances de deux inventées ne dirait rien de l'app.
    private static let shippedShapedManifest = MapTileManifest(
        tile: 512,
        base: 4096,
        levels: [
            .init(side: 9216, count: 18, uniform: [:]),
            .init(side: 18432, count: 36, uniform: [:]),
        ]
    )
```

Puis, à la fin de la suite (après `aTileFrameTilesTheContentSpaceExactly`, avant l'accolade fermante ligne 134) :

```swift
    // MARK: - Plafond de zoom

    /// Les deux valeurs iPhone d'aujourd'hui, retrouvées par la formule. C'est
    /// la seule chose qui autorise à remplacer deux constantes par un calcul :
    /// s'il ne les redonnait pas, il changerait le comportement en douce.
    @Test func theCeilingReproducesTodaysIPhoneConstants() {
        let pyramided = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 3
        )
        #expect(abs(pyramided - 3.3) < 0.0001)
        let bare = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: nil, displayScale: 3)
        #expect(abs(bare - 2.5) < 0.0001)
    }

    /// Et ce qu'elles deviennent sur un appareil ×2 : la même finesse à
    /// l'écran demande un zoom une fois et demie plus grand. C'est tout
    /// l'objet de ce chantier — l'iPad s'arrêtait à 73 % de ce qu'il embarque.
    @Test func theCeilingRisesOnATwoTimesDevice() {
        let pyramided = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 2
        )
        #expect(abs(pyramided - 4.95) < 0.0001)
        let bare = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: nil, displayScale: 2)
        #expect(abs(bare - 3.75) < 0.0001)
    }

    /// La même finesse à l'écran, littéralement : à leurs plafonds respectifs,
    /// les deux appareils réclament le même nombre de pixels source par point
    /// d'écran. Aucune des deux fonctions testées ne connaît l'autre appareil,
    /// donc cette égalité n'est pas une tautologie — c'est la propriété que la
    /// formule est censée produire.
    @Test func bothDevicesEndOnTheSameSourcePixelDensity() {
        let onThree = MapTileSet.displayablePixels(
            zoomScale: MapTileSet.maximumZoomScale(contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 3),
            contentSize: 2048, displayScale: 3
        )
        let onTwo = MapTileSet.displayablePixels(
            zoomScale: MapTileSet.maximumZoomScale(contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 2),
            contentSize: 2048, displayScale: 2
        )
        #expect(abs(onThree - onTwo) < 1)
        #expect(abs(onThree - 18432 * 1.10) < 1)
    }

    /// Un manifeste sans niveau n'est pas une pyramide : il retombe sur le
    /// socle, et non sur une division par un côté nul.
    @Test func aLevellessManifestFallsBackToTheBareBase() {
        let empty = MapTileManifest(tile: 512, base: 4096, levels: [])
        let ceiling = MapTileSet.maximumZoomScale(contentSize: 2048, manifest: empty, displayScale: 3)
        #expect(abs(ceiling - 2.5) < 0.0001)
    }

    /// Deux entrées dégénérées, toutes deux atteignables : une vue pas encore
    /// posée a une échelle d'affichage de 0, et un contenu de côté nul rendrait
    /// un plafond infini qu'`UIScrollView` accepterait sans broncher.
    ///
    /// La spec en listait une troisième — « tolérance nulle » — qui n'a plus
    /// d'objet : la tolérance n'est pas un paramètre mais une constante du
    /// type, donc aucun appelant ne peut la mettre à zéro. Le cas structurel
    /// équivalent, un manifeste sans niveau, est couvert juste au-dessus.
    @Test func theCeilingSurvivesDegenerateInputs() {
        let noScale = MapTileSet.maximumZoomScale(
            contentSize: 2048, manifest: Self.shippedShapedManifest, displayScale: 0
        )
        #expect(abs(noScale - 18432 * 1.10 / 2048) < 0.0001)
        let noContent = MapTileSet.maximumZoomScale(
            contentSize: 0, manifest: Self.shippedShapedManifest, displayScale: 3
        )
        #expect(noContent == 1)
    }
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapTileSetTests > /tmp/t1.log 2>&1 &
```
Attendre, puis `grep -c "Test run with" /tmp/t1.log` ; `pkill -f xcodebuild`.
Attendu : ÉCHEC de compilation, `value of type 'MapTileSet' has no member 'maximumZoomScale'`.

- [ ] **Step 3 : écrire l'implémentation minimale**

Ajouter à la fin de `enum MapTileSet` dans `NeonCompass/Core/Map/MapTileSet.swift`, après `frame(for:contentSize:manifest:)` :

```swift
    /// Agrandissement toléré au-delà du niveau le plus fin.
    ///
    /// 1,10 n'est pas un arbitrage neuf : c'est exactement ce que le plafond
    /// de 3,3 réclamait déjà sur un appareil ×3 — 2 048 pt × 3,3 × 3 font
    /// 20 275 px demandés aux 18 432 du niveau le plus fin. La constante ne
    /// fait que nommer ce qu'on faisait.
    static let pyramidUpscale: CGFloat = 1.10

    /// Sans pyramide, on tolère 3,75× — là encore ce que le plafond de 2,5
    /// réclamait déjà sur ×3 : 2 048 × 2,5 × 3 font 15 360 px demandés aux
    /// 4 096 du socle. Bien plus permissif que 1,10, et ce n'est pas une
    /// inconséquence : la carte de référence n'a rien de plus fin à montrer,
    /// donc son plafond arbitre entre « on voit du flou » et « on ne peut plus
    /// s'approcher du tout », pas entre deux niveaux de netteté.
    static let baseUpscale: CGFloat = 3.75

    /// Côté du socle quand aucun manifeste ne le déclare, en pixels.
    ///
    /// Une carte sans pyramide n'a pas de manifeste, donc pas d'endroit où
    /// lire ce nombre. Ce n'est pas une convention pour autant :
    /// `MapArtResourcesTests.everyBaseImageIsShippedAtFourThousandNinetySix`
    /// l'épingle sur les vrais fichiers, tous les quatre.
    static let unpyramidedBaseSide: CGFloat = 4096

    /// Le plafond de zoom, en géométrie plutôt qu'en constante.
    ///
    /// Le contenu fait `contentSize` points pour un certain nombre de pixels
    /// d'image, et un écran en rend `zoom × displayScale` par point. Le zoom
    /// au-delà duquel on agrandirait plus que la tolérance est donc :
    ///
    ///     plafond = côtéSource × tolérance ÷ (contentSize × displayScale)
    ///
    /// Un appareil ×2 y gagne une fois et demie le plafond d'un ×3, pour la
    /// MÊME finesse à l'écran. C'est le défaut que ce calcul corrige : à
    /// plafond constant, l'iPad n'affichait que 73 % de la finesse linéaire
    /// qu'il embarque.
    ///
    /// Le plancher de 1 n'est pas décoratif : `UIScrollView` accepte sans
    /// broncher un `maximumZoomScale` sous son `minimumZoomScale`, et le
    /// résultat est une carte qu'on ne peut plus manipuler du tout.
    static func maximumZoomScale(
        contentSize: CGFloat,
        manifest: MapTileManifest?,
        displayScale: CGFloat
    ) -> CGFloat {
        guard contentSize > 0 else { return 1 }
        let sourceSide: CGFloat
        let tolerance: CGFloat
        if let finest = manifest?.levels.last?.side, finest > 0 {
            sourceSide = CGFloat(finest)
            tolerance = pyramidUpscale
        } else {
            sourceSide = unpyramidedBaseSide
            tolerance = baseUpscale
        }
        return max(sourceSide * tolerance / (contentSize * max(displayScale, 1)), 1)
    }
```

- [ ] **Step 4 : lancer les tests et vérifier qu'ils passent**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapTileSetTests > /tmp/t1.log 2>&1 &
```
Attendu : `Test run with 16 tests` (11 existants + 5 nouveaux), zéro échec. Lire la ligne, pas seulement `TEST SUCCEEDED`. Puis `pkill -f xcodebuild`.

- [ ] **Step 5 : prouver que le contrôle sait échouer**

Changer temporairement `pyramidUpscale` de `1.10` à `1.20`, relancer la suite : `theCeilingReproducesTodaysIPhoneConstants`, `theCeilingRisesOnATwoTimesDevice`, `bothDevicesEndOnTheSameSourcePixelDensity` et `theCeilingSurvivesDegenerateInputs` doivent tomber. Remettre `1.10` et relancer : tout repasse. Sans cette étape, un test qui ne sait qu'approuver est indiscernable d'un bon.

- [ ] **Step 6 : commit**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git add NeonCompass/Core/Map/MapTileSet.swift NeonCompassTests/Map/MapTileSetTests.swift
git status --short   # Localizable.xcstrings ne doit PAS y figurer
git commit -F /tmp/msg-t1.txt
```

Contenu de `/tmp/msg-t1.txt` (à écrire avec l'outil Write) :

```
feat(carte): le plafond de zoom devient une fonction de l'appareil

Une constante là où c'est une géométrie : 18 432 px de niveau le plus fin
sur 2 048 pt de contenu font 9,0 px source par point, que l'écran rend à
zoom x displayScale. Le plafond unique de 3,3 demandait donc 1,10x
d'agrandissement sur un appareil x3 mais 0,73x sur un x2.

Les deux valeurs d'aujourd'hui retombent exactement de la formule sur x3,
et c'est la seule chose qui autorise le remplacement. Branchement dans le
moteur au commit suivant.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

### Task 2 : brancher le plafond dans le moteur

**Files:**
- Modify: `NeonCompass/Core/Map/MapScrollView.swift` — trois endroits : `makeUIView` (enregistrement du changement de trait, vers la ligne 685), `setArt` (la ligne `scrollView?.maximumZoomScale = tileManifest == nil ? 2.5 : 3.3`, vers la ligne 958), et un nouveau membre du `Coordinator`.

**Interfaces:**
- Consomme (tâche 1) : `MapTileSet.maximumZoomScale(contentSize:manifest:displayScale:)`.
- Produit : rien pour les tâches suivantes. `Coordinator.applyMaximumZoomScale()` reste `fileprivate`.

**Contexte que la tâche ne peut pas deviner :** `Coordinator` est une classe `NSObject` (elle porte déjà `@objc func handleLongPress`), elle détient `scrollView`, `tileManifest` et `contentFullSize`. `maximumZoomScale` n'est posé QUE dans `setArt`, jamais dans `makeUIView` — c'est écrit dans un commentaire sur place, et ce plan conserve cette autorité unique.

- [ ] **Step 1 : remplacer la constante par l'appel**

Dans `setArt`, remplacer tout le bloc de commentaire qui précède `scrollView?.maximumZoomScale` ET la ligne elle-même. Chercher le commentaire commençant par `// Le plafond de zoom dépend de la carte, parce que ce qu'il y a` et remplacer depuis cette ligne jusqu'à `scrollView?.maximumZoomScale = tileManifest == nil ? 2.5 : 3.3` inclus, par :

```swift
                // Le plafond dépend de la carte, parce que ce qu'il y a à VOIR
                // en dépend — et de l'appareil, parce qu'un point d'écran ne
                // vaut pas le même nombre de pixels partout. `MapTileSet` porte
                // la formule et les deux tolérances ; ici on ne fait que
                // demander.
                applyMaximumZoomScale()
```

- [ ] **Step 2 : ajouter la méthode au Coordinator**

Juste au-dessus de `fileprivate func setArt(game:style:)` dans `MapScrollView.swift` :

```swift
        /// Pose le plafond pour la carte courante et l'appareil courant.
        ///
        /// Appelée depuis `setArt` (la carte a changé) et depuis
        /// l'enregistrement de `UITraitDisplayScale` posé dans `makeUIView`
        /// (l'appareil a changé — écran externe, ou simple arrivée dans une
        /// fenêtre, où l'échelle vaut 0 avant).
        fileprivate func applyMaximumZoomScale() {
            guard let scrollView else { return }
            let ceiling = MapTileSet.maximumZoomScale(
                contentSize: contentFullSize,
                manifest: tileManifest,
                displayScale: scrollView.traitCollection.displayScale
            )
            scrollView.maximumZoomScale = ceiling
            // `maximumZoomScale` n'est PAS rétroactif : abaisser le plafond ne
            // ramène pas le zoom courant sous lui, et l'utilisateur reste
            // au-delà jusqu'à ce qu'il pince. Sur le chemin « la carte
            // change » c'était sans conséquence — `updateUIView` appelle
            // `refit()` avant nous, donc le zoom est déjà au repos. Le chemin
            // « l'échelle d'affichage change » n'a pas ce filet.
            if scrollView.zoomScale > ceiling { scrollView.zoomScale = ceiling }
        }
```

- [ ] **Step 3 : réagir au changement d'échelle d'affichage**

Dans `makeUIView`, immédiatement après `scrollView.delegate = context.coordinator` :

```swift
        // `registerForTraitChanges` et non `traitCollectionDidChange`, qui est
        // déprécié depuis iOS 17 — et qui aurait en prime réveillé le
        // coordinateur pour chaque trait, alors qu'un seul nous concerne.
        //
        // Forme cible/action et non bloc : UIKit ne retient la cible que
        // faiblement, donc rien à désinscrire et rien qui prolonge la vie du
        // coordinateur. Pas de cycle à craindre dans un sens ni dans l'autre —
        // le coordinateur ne retient le `scrollView` que faiblement.
        //
        // Ce n'est pas de la prévoyance pour écrans externes : à l'instant où
        // `makeUIView` s'exécute, la vue n'est dans aucune fenêtre et son
        // échelle d'affichage vaut 0. La vraie valeur arrive par ici.
        _ = scrollView.registerForTraitChanges(
            [UITraitDisplayScale.self],
            target: context.coordinator,
            action: #selector(Coordinator.displayScaleDidChange)
        )
```

Et dans le `Coordinator`, juste après `applyMaximumZoomScale()` :

```swift
        @objc fileprivate func displayScaleDidChange() { applyMaximumZoomScale() }
```

- [ ] **Step 4 : la bretelle du premier tour**

Dans `makeUIView`, le bloc `DispatchQueue.main.async` qui suit `setArt` appelle déjà `sync`. Y ajouter le plafond, en première ligne du bloc après le `guard` :

```swift
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView else { return }
            // La vue est dans une fenêtre à ce tour-ci, donc son échelle
            // d'affichage est réelle. Ceinture : si l'enregistrement de trait
            // ne se déclenche pas pour l'entrée en fenêtre, le plafond serait
            // resté celui d'une échelle de 0.
            context.coordinator.applyMaximumZoomScale()
            context.coordinator.sync(scrollView)
        }
```

- [ ] **Step 5 : construire et lancer la suite complète**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test > /tmp/t2.log 2>&1 &
```
Attendre l'apparition de `Test run with` dans `/tmp/t2.log`, lire le compte et le nombre d'échecs, puis `pkill -f xcodebuild`.
Attendu : zéro échec. Ce branchement n'a pas de test unitaire propre — le `Coordinator` est `fileprivate`, donc hors de portée de `@testable`. Sa preuve visuelle est la tâche 5.

- [ ] **Step 6 : vérifier qu'aucun artefact n'est emporté**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git status --short
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
```

- [ ] **Step 7 : commit**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git add NeonCompass/Core/Map/MapScrollView.swift
git commit -F /tmp/msg-t2.txt
```

`/tmp/msg-t2.txt` :

```
feat(carte): l'iPad monte a 4,95, l'iPhone reste a 3,3

Le moteur demande son plafond a MapTileSet plutot que de le choisir. Deux
appels : au changement de carte, et au changement d'echelle d'affichage —
ce second n'est pas de la prevoyance, l'echelle vaut 0 tant que la vue
n'est dans aucune fenetre.

Le rabot sur le zoom courant n'est pas redondant : maximumZoomScale n'est
pas retroactif, et le chemin « l'echelle change » n'a pas le refit() qui
couvrait le chemin « la carte change ».

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

### Task 3 : la géométrie et l'image du fondu, en fonctions pures

**Files:**
- Create: `NeonCompass/Core/Map/MapEdgeFadeImage.swift`
- Modify: `NeonCompass/Core/Map/MapGeometry.swift` (ajout à la fin de l'`enum MapGeometry`, après `coverZoomScale` ligne 222, et une structure au-dessus de l'`enum`)
- Modify: `NeonCompass/Core/DesignSystem/NCColor.swift` (lignes 3-4)
- Test: `NeonCompassTests/Map/MapGeometryTests.swift` (ajout)
- Create: `NeonCompassTests/Map/MapEdgeFadeImageTests.swift`

**Interfaces:**
- Consomme : `NCColor.RGBA` (`red`/`green`/`blue`/`alpha` en `Double` de 0 à 1).
- Produit, pour la tâche 4 :
  - `struct MapEdgeFade: Equatable, Sendable { let contentsScale: CGFloat; let opacity: Float }`
  - `MapGeometry.edgeFade(band: CGFloat, contentSize: CGSize, zoomScale: CGFloat, displayScale: CGFloat, in bounds: CGSize) -> MapEdgeFade`
  - `MapEdgeFadeImage.band: CGFloat` (vaut 80)
  - `MapEdgeFadeImage.bandPixels(displayScale: CGFloat) -> Int`
  - `MapEdgeFadeImage.contentsCenter(bandPixels: Int) -> CGRect`
  - `MapEdgeFadeImage.make(bandPixels: Int, color: NCColor.RGBA) -> CGImage?`
  - `NCColor.nightSkyRGBA: NCColor.RGBA`

**Le point de conception que la tâche doit comprendre avant d'écrire :** le calque de fondu vit dans l'espace de CONTENU, que le zoom agrandit. Si l'épaisseur de la bande était fixée dans cet espace, elle vaudrait 80 pt d'écran à un seul zoom — et 934 pt au repos sur iPhone. La bande est donc gravée dans l'image en PIXELS, et c'est `contentsScale = displayScale × zoom` qui fait qu'un pixel de l'image vaut un pixel de l'appareil quel que soit le zoom. Rien à redimensionner, rien à regraver.

- [ ] **Step 1 : exposer la couleur de fond en RGBA**

Dans `NeonCompass/Core/DesignSystem/NCColor.swift`, remplacer la ligne 4 :

```swift
    static let nightSky = Color(RGBA(hex: "#0A081A")!)
```

par :

```swift
    /// La forme composante, et non seulement la `Color` : Core Graphics et
    /// Core Animation ne savent pas lire une `Color` SwiftUI, et le fondu des
    /// bords de la carte doit peindre exactement cette teinte-là. Une seule
    /// écriture de l'hexadécimal, dont les deux formes descendent.
    static let nightSkyRGBA = RGBA(hex: "#0A081A")!
    static let nightSky = Color(nightSkyRGBA)
```

- [ ] **Step 2 : écrire les tests de géométrie qui échouent**

Ajouter à la fin de la suite dans `NeonCompassTests/Map/MapGeometryTests.swift` (avant l'accolade fermante de la structure de tests) :

```swift
    // MARK: - Fondu des bords

    /// Les deux appareils, à leur zoom de REPOS. Ce ne sont pas des mesures
    /// prises sur un simulateur : ce sont les tailles logiques des deux
    /// appareils visés, et le zoom de repos qui en découle (la carte couvre
    /// l'écran sans bande vide, donc `bounds.height / 2 048`).
    private static let phoneBounds = CGSize(width: 402, height: 874)
    private static let padBounds = CGSize(width: 1032, height: 1376)
    private static let mapSize = CGSize(width: 2048, height: 2048)

    /// Au repos, aucun fondu — et ce n'est pas un réglage de confort.
    ///
    /// Le zoom de repos fait affleurer la carte à DEUX des quatre bords de
    /// l'écran, exactement. Un fondu toujours actif y poserait une vignette de
    /// 80 pt en haut et en bas, alors qu'au repos il n'y a aucun bord à
    /// masquer : la découpe franche n'est visible qu'en débord.
    @Test func noFadeAtRestOnEitherDevice() {
        let phone = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            zoomScale: Self.phoneBounds.height / 2048, displayScale: 3, in: Self.phoneBounds
        )
        #expect(phone.opacity == 0)
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            zoomScale: Self.padBounds.height / 2048, displayScale: 2, in: Self.padBounds
        )
        #expect(pad.opacity == 0)
    }

    /// Et il est entier dès que les quatre bords ont quitté l'écran d'au moins
    /// la largeur du fondu — c'est-à-dire bien avant le premier zoom où l'on
    /// peut déborder assez pour voir un coin.
    @Test func theFadeIsWholeAtTheCeiling() {
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            zoomScale: 4.95, displayScale: 2, in: Self.padBounds
        )
        #expect(pad.opacity == 1)
    }

    /// Entre les deux, il entre en scène exactement à la vitesse à laquelle le
    /// bord quitte l'écran. À ce zoom l'écart vertical vaut 40 pt, soit la
    /// moitié de la bande — le calcul de l'attendu : (2 048 × 0,7109375 −
    /// 1 376) / 2 = 40.
    @Test func theFadeRampsWithHowFarTheEdgeHasLeftTheScreen() {
        let pad = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize,
            zoomScale: 0.7109375, displayScale: 2, in: Self.padBounds
        )
        #expect(abs(pad.opacity - 0.5) < 0.001)
    }

    /// Le cœur du chantier : 80 points d'ÉCRAN, à tous les zooms et sur les
    /// deux appareils. Le test refait le trajet dans l'autre sens — combien de
    /// points d'écran occupe la bande gravée, sachant l'échelle rendue — plutôt
    /// que de relire la formule qu'il vérifie. Une implémentation qui poserait
    /// la bande en points de CONTENU passerait le zoom 1 et échouerait partout
    /// ailleurs.
    @Test func theBandMeasuresEightyScreenPointsAtEveryZoom() {
        for (displayScale, bounds) in [(CGFloat(3), Self.phoneBounds), (CGFloat(2), Self.padBounds)] {
            let pixels = CGFloat(MapEdgeFadeImage.bandPixels(displayScale: displayScale))
            for zoom in [bounds.height / 2048, 1.0, 2.5, 3.3, 4.95] as [CGFloat] {
                let fade = MapGeometry.edgeFade(
                    band: MapEdgeFadeImage.band, contentSize: Self.mapSize,
                    zoomScale: zoom, displayScale: displayScale, in: bounds
                )
                let onScreen = pixels / fade.contentsScale * zoom
                #expect(abs(onScreen - 80) < 0.01, "displayScale \(displayScale), zoom \(zoom)")
            }
        }
    }

    /// Un zoom nul est atteignable — `contentNativeSize` vaut zéro avant le
    /// premier `layoutSubviews`. Il ne doit produire ni infini ni NaN, et
    /// surtout pas de calque visible.
    @Test func aZeroZoomYieldsNothingVisibleRatherThanInfinity() {
        let fade = MapGeometry.edgeFade(
            band: 80, contentSize: Self.mapSize, zoomScale: 0, displayScale: 2, in: Self.padBounds
        )
        #expect(fade.opacity == 0)
        #expect(fade.contentsScale > 0)
        #expect(fade.contentsScale.isFinite)
    }
```

- [ ] **Step 3 : écrire les tests d'image qui échouent**

Créer `NeonCompassTests/Map/MapEdgeFadeImageTests.swift` :

```swift
import Testing
import Foundation
import CoreGraphics
@testable import NeonCompass

/// L'image du fondu est un carré de neuf tranches : les quatre coins portent
/// la retombée en deux dimensions, les quatre bandes la portent en une seule
/// et sont constantes le long de leur longueur — condition pour que
/// `contentsCenter` puisse les étirer sur 10 000 points sans les déformer.
struct MapEdgeFadeImageTests {
    private static let band = 8
    private static let side = 2 * band + 2

    /// Rend l'octet alpha du pixel, ou nil si l'image n'a pas la forme attendue.
    private static func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8? {
        guard image.bitsPerPixel == 32, image.alphaInfo == .premultipliedLast,
              let provider = image.dataProvider?.data else { return nil }
        let data = provider as Data
        return data[y * image.bytesPerRow + x * 4 + 3]
    }

    private static func rgb(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard let provider = image.dataProvider?.data else { return nil }
        let data = provider as Data
        let i = y * image.bytesPerRow + x * 4
        return (data[i], data[i + 1], data[i + 2])
    }

    @Test func theImageIsTwiceTheBandPlusTheStretchableCentre() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        #expect(image.width == Self.side)
        #expect(image.height == Self.side)
    }

    /// Opaque au bord, transparent au centre : les deux extrémités de la
    /// rampe. Sans la première, le bord de la carte resterait visible ; sans la
    /// seconde, le fondu couvrirait la carte entière d'un voile.
    @Test func theRampRunsFromOpaqueEdgeToTransparentCentre() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        #expect(Self.alpha(image, x: 0, y: 0) == 255)
        #expect(Self.alpha(image, x: 0, y: Self.side / 2) == 255)
        #expect(Self.alpha(image, x: Self.side / 2, y: Self.side / 2) == 0)
    }

    /// Au bord, la couleur est celle du fond de l'app et pas une autre : c'est
    /// tout l'objet du fondu, faire se rejoindre la carte et le vide.
    @Test func theOpaqueEdgeIsExactlyTheAppBackground() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let channels = try #require(Self.rgb(image, x: 0, y: Self.side / 2))
        #expect(channels.0 == 10)
        #expect(channels.1 == 8)
        #expect(channels.2 == 26)
    }

    /// À mi-bande, à mi-chemin — le lissage de Hermite vaut 0,5 en son milieu
    /// comme une rampe linéaire, ce qui rend l'attendu vérifiable de tête.
    @Test func theRampIsHalfwayAtHalfTheBand() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let a = try #require(Self.alpha(image, x: Self.band / 2, y: Self.side / 2))
        #expect(abs(Int(a) - 128) <= 2)
    }

    /// La propriété qui autorise `contentsCenter` : dans une bande, l'alpha ne
    /// dépend que de la distance au bord de CETTE bande. Sans elle, l'étirement
    /// du centre déformerait le dégradé.
    @Test func aBandIsConstantAlongItsLength() throws {
        let image = try #require(MapEdgeFadeImage.make(bandPixels: Self.band, color: NCColor.nightSkyRGBA))
        let reference = try #require(Self.alpha(image, x: 3, y: Self.band))
        for y in Self.band...(Self.side - 1 - Self.band) {
            #expect(Self.alpha(image, x: 3, y: y) == reference)
        }
    }

    /// Le rectangle étirable désigne les 2 px du centre, pas un de plus : y
    /// inclure un pixel de la rampe étirerait une valeur intermédiaire sur
    /// toute la carte.
    @Test func theStretchableRectIsTheTwoCentrePixels() {
        let rect = MapEdgeFadeImage.contentsCenter(bandPixels: Self.band)
        #expect(abs(rect.minX - 8.0 / 18.0) < 0.0001)
        #expect(abs(rect.minY - 8.0 / 18.0) < 0.0001)
        #expect(abs(rect.width - 2.0 / 18.0) < 0.0001)
        #expect(abs(rect.height - 2.0 / 18.0) < 0.0001)
    }

    /// L'épaisseur en pixels suit l'appareil, pour que 80 points d'écran en
    /// fassent toujours 80.
    @Test func theBandInPixelsFollowsTheDevice() {
        #expect(MapEdgeFadeImage.band == 80)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 2) == 160)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 3) == 240)
        #expect(MapEdgeFadeImage.bandPixels(displayScale: 0) == 80)
    }

    @Test func aZeroBandYieldsNoImageRatherThanACrash() {
        #expect(MapEdgeFadeImage.make(bandPixels: 0, color: NCColor.nightSkyRGBA) == nil)
    }
}
```

- [ ] **Step 4 : lancer les deux suites pour vérifier qu'elles échouent**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapGeometryTests \
  -only-testing:NeonCompassTests/MapEdgeFadeImageTests > /tmp/t3.log 2>&1 &
```
Attendu : ÉCHEC de compilation (`MapEdgeFadeImage` et `MapGeometry.edgeFade` n'existent pas). Puis `pkill -f xcodebuild`.

- [ ] **Step 5 : écrire la géométrie**

Dans `NeonCompass/Core/Map/MapGeometry.swift`, ajouter juste AVANT la ligne `enum MapGeometry {` :

```swift
/// Ce qu'il faut poser sur le calque de fondu pour l'état courant.
///
/// Deux nombres, et pas un de plus : le calque ne change ni de cadre ni
/// d'image quand on zoome, ce qui est tout l'intérêt du procédé.
struct MapEdgeFade: Equatable, Sendable {
    /// `contentsScale` du calque.
    ///
    /// Le calque vit dans l'espace de CONTENU, que le zoom agrandit. Porter
    /// son échelle à `displayScale × zoom` fait qu'un pixel de l'image vaut un
    /// pixel de l'appareil : la bande gravée mesure alors le même nombre de
    /// points d'ÉCRAN à tous les zooms, sans qu'on regrave ni redimensionne
    /// quoi que ce soit.
    let contentsScale: CGFloat

    /// Le fondu entre en scène à mesure que le bord quitte l'écran.
    ///
    /// Au repos la carte affleure exactement deux des quatre bords — c'est la
    /// définition de l'échelle de repos, qui couvre l'écran sans bande vide.
    /// Un fondu toujours actif y poserait donc une vignette de 80 pt en haut
    /// et en bas, alors qu'au repos il n'y a aucun bord à masquer.
    let opacity: Float
}
```

Et à la fin de l'`enum MapGeometry`, après `coverZoomScale` :

```swift
    /// L'état du calque de fondu, pour un zoom et un appareil donnés.
    ///
    /// - Parameter band: l'épaisseur voulue, en points d'ÉCRAN.
    ///
    /// L'opacité se règle sur le bord le PLUS PROCHE de l'écran, les quatre
    /// côtés partageant un seul calque. Au repos ce minimum vaut zéro (deux
    /// bords affleurent) et le fondu est absent ; il est entier dès que les
    /// quatre bords ont pris au moins la largeur de la bande d'avance.
    static func edgeFade(
        band: CGFloat,
        contentSize: CGSize,
        zoomScale: CGFloat,
        displayScale: CGFloat,
        in bounds: CGSize
    ) -> MapEdgeFade {
        let zoom = max(zoomScale, 0.0001)
        let offScreen = min(
            (contentSize.width * zoom - bounds.width) / 2,
            (contentSize.height * zoom - bounds.height) / 2
        )
        let ramp = band > 0 ? min(max(offScreen / band, 0), 1) : 0
        return MapEdgeFade(
            contentsScale: max(displayScale, 1) * zoom,
            opacity: Float(ramp)
        )
    }
```

- [ ] **Step 6 : écrire l'image**

Créer `NeonCompass/Core/Map/MapEdgeFadeImage.swift` :

```swift
import CoreGraphics
import Foundation

/// L'image du fondu des bords : un carré dont les `band` pixels de pourtour
/// passent de la couleur du fond au transparent, et dont le centre — 2 px —
/// est entièrement transparent.
///
/// Pourquoi une image et non quatre dégradés posés à la main : `contentsCenter`
/// étire ces 2 px sur toute la surface du calque, donc une image de quelques
/// centaines de kilo-octets habille une carte de 10 000 points de côté, et les
/// quatre coins sont peints une fois pour toutes plutôt que raccordés.
///
/// Pourquoi pas dans les PNG des socles : l'épaisseur est en points d'ÉCRAN.
/// Cuite dans l'image, elle vaudrait 16 points de contenu au zoom maximal et
/// 187 au repos — le fondu grossirait avec la carte, ce qui est exactement ce
/// qu'on ne veut pas.
enum MapEdgeFadeImage {
    /// L'épaisseur du fondu, en points d'écran.
    static let band: CGFloat = 80

    /// La même, en pixels de l'appareil — l'épaisseur à graver.
    static func bandPixels(displayScale: CGFloat) -> Int {
        Int((band * max(displayScale, 1)).rounded())
    }

    /// Le rectangle étirable, en coordonnées unitaires — à poser sur
    /// `CALayer.contentsCenter`. Il désigne les 2 px du centre, pas un de
    /// plus : y inclure un pixel de la rampe étirerait une valeur
    /// intermédiaire sur toute la carte.
    static func contentsCenter(bandPixels: Int) -> CGRect {
        let side = CGFloat(2 * bandPixels + 2)
        return CGRect(
            x: CGFloat(bandPixels) / side, y: CGFloat(bandPixels) / side,
            width: 2 / side, height: 2 / side
        )
    }

    /// - Parameter bandPixels: l'épaisseur de la bande, en pixels de l'image.
    static func make(bandPixels: Int, color: NCColor.RGBA) -> CGImage? {
        guard bandPixels > 0 else { return nil }
        let side = 2 * bandPixels + 2
        let band = Double(bandPixels)
        let red = min(max(color.red, 0), 1) * 255
        let green = min(max(color.green, 0), 1) * 255
        let blue = min(max(color.blue, 0), 1) * 255
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            let dy = Double(min(y, side - 1 - y))
            for x in 0..<side {
                // Distance au bord le plus proche : le minimum sur les deux
                // axes. Ce choix laisse chaque bande constante le long de sa
                // longueur — condition de `contentsCenter` — et chanfreine les
                // coins, ce qui ne se distingue pas d'un coin radial à cette
                // échelle.
                let dx = Double(min(x, side - 1 - x))
                let t = min(min(dx, dy) / band, 1)
                // Lissage de Hermite : une rampe linéaire laisse une arête
                // visible là où le fondu s'arrête, les dérivées nulles aux deux
                // bouts l'effacent. Vaut 0,5 en son milieu comme la linéaire.
                let alpha = 1 - t * t * (3 - 2 * t)
                let i = (y * side + x) * 4
                // Prémultiplié : les canaux portent déjà le facteur alpha.
                pixels[i] = UInt8((red * alpha).rounded())
                pixels[i + 1] = UInt8((green * alpha).rounded())
                pixels[i + 2] = UInt8((blue * alpha).rounded())
                pixels[i + 3] = UInt8((255 * alpha).rounded())
            }
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            // `makeImage` prend une copie du tampon, donc l'image survit à la
            // portée du pointeur.
            return context.makeImage()
        }
    }
}
```

- [ ] **Step 7 : lancer les tests et vérifier qu'ils passent**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/MapGeometryTests \
  -only-testing:NeonCompassTests/MapEdgeFadeImageTests > /tmp/t3.log 2>&1 &
```
Attendu : `Test run with` avec les 8 tests de `MapEdgeFadeImageTests` plus ceux de `MapGeometryTests` (existants + 5), zéro échec. Puis `pkill -f xcodebuild`.

- [ ] **Step 8 : prouver que le contrôle sait échouer**

Remplacer temporairement, dans `edgeFade`, `contentsScale: max(displayScale, 1) * zoom` par `contentsScale: max(displayScale, 1)` — c'est exactement le bug « la bande est en points de contenu ». Relancer : `theBandMeasuresEightyScreenPointsAtEveryZoom` doit tomber sur tous les zooms sauf 1,0. Remettre, relancer, tout repasse.

- [ ] **Step 9 : commit**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git add NeonCompass/Core/Map/MapEdgeFadeImage.swift NeonCompass/Core/Map/MapGeometry.swift \
        NeonCompass/Core/DesignSystem/NCColor.swift \
        NeonCompassTests/Map/MapEdgeFadeImageTests.swift NeonCompassTests/Map/MapGeometryTests.swift \
        NeonCompass.xcodeproj/project.pbxproj
git status --short
git commit -F /tmp/msg-t3.txt
```

`/tmp/msg-t3.txt` :

```
feat(carte): la geometrie et l'image du fondu des bords

80 points d'ECRAN, ce qui interdit de les cuire dans les PNG : ils
vaudraient 16 points de contenu au zoom maximal et 187 au repos. Une image
de neuf tranches, dont l'echelle suit le zoom — le calque ne change ni de
cadre ni d'image quand on zoome.

L'opacite se regle sur le bord le plus proche de l'ecran, et vaut donc zero
au repos : l'echelle de repos fait affleurer la carte a deux des quatre
bords, ou un fondu permanent poserait une vignette au lieu de masquer une
decoupe qui n'est pas la.

Branchement au commit suivant.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

### Task 4 : poser le calque de fondu

**Files:**
- Modify: `NeonCompass/Core/Map/MapTileLayerView.swift` — trois membres privés, quatre lignes dans `init` après `layer.addSublayer(baseLayer)` (vers la ligne 90), et une méthode publique nouvelle.
- Modify: `NeonCompass/Core/Map/MapScrollView.swift` — la couleur de fond (`scrollView.backgroundColor = .black`, vers la ligne 687) et un appel dans `sync` (vers la ligne 1087).

**Interfaces:**
- Consomme (tâche 3) : `MapGeometry.edgeFade(band:contentSize:zoomScale:displayScale:in:) -> MapEdgeFade` (`.contentsScale`, `.opacity`), `MapEdgeFadeImage.band`, `.bandPixels(displayScale:)`, `.contentsCenter(bandPixels:)`, `.make(bandPixels:color:)`, `NCColor.nightSkyRGBA`, `NCColor.nightSky`.
- Produit : `MapTileLayerView.updateEdgeFade(zoomScale:displayScale:viewportSize:)`, appelée par le `Coordinator`.

**Deux pièges que la tâche doit éviter :**
1. `update(visibleContentRect:zoomScale:displayScale:)` rend la main dès sa première ligne quand la carte n'a pas de manifeste — ce qui est le cas de la carte de référence, celle sur laquelle l'app OUVRE. Le fondu ne peut donc pas être posé depuis `update` : il lui faut son propre appel, avant.
2. Un calque ajouté dans `init` se retrouve SOUS les tuiles, que `place` ajoute après coup. D'où `zPosition`, et non l'ordre d'insertion.

- [ ] **Step 1 : les membres du calque**

Dans `NeonCompass/Core/Map/MapTileLayerView.swift`, juste après la déclaration de `baseLayer` (vers la ligne 32) :

```swift
    /// Le fondu des bords, au-dessus des tuiles.
    ///
    /// Les épingles restent nettes sans qu'on ait rien à faire : elles vivent
    /// dans une AUTRE vue du même conteneur, posée au-dessus de celle-ci.
    ///
    /// `zPosition` et non l'ordre d'insertion : `place` ajoute des tuiles après
    /// coup, et une couche ajoutée dans `init` passerait dessous.
    private let fadeLayer = CALayer()

    /// L'échelle d'affichage qui a servi à graver l'image du fondu. La
    /// regraver coûte une boucle sur ~300 000 pixels, donc on ne la refait
    /// qu'au changement d'appareil — pas à chaque image de zoom.
    private var fadeImageScale: CGFloat = 0
```

- [ ] **Step 2 : le calque dans `init`**

Dans `init(contentSize:)`, juste après `layer.addSublayer(baseLayer)` :

```swift
        fadeLayer.frame = bounds
        fadeLayer.zPosition = 1
        // Invisible tant que `updateEdgeFade` n'a rien dit : au repos c'est
        // l'état définitif, et le premier `sync` arrive au tour de boucle
        // suivant.
        fadeLayer.opacity = 0
        // `contentsCenter` n'est honoré qu'avec une gravité redimensionnante ;
        // c'est la valeur par défaut, posée ici pour que la relecture n'ait
        // pas à le savoir.
        fadeLayer.contentsGravity = .resize
        fadeLayer.actions = [
            "contents": NSNull(), "contentsScale": NSNull(),
            "opacity": NSNull(), "position": NSNull(), "bounds": NSNull()
        ]
        layer.addSublayer(fadeLayer)
```

- [ ] **Step 3 : la méthode de mise à jour**

Ajouter dans `MapTileLayerView`, juste AVANT `func update(visibleContentRect:zoomScale:displayScale:)` :

```swift
    /// Pose le fondu pour l'état courant.
    ///
    /// Appelée hors de `update`, et c'est délibéré : `update` rend la main dès
    /// sa première ligne quand la carte n'a pas de manifeste — la carte de
    /// référence, celle sur laquelle l'app ouvre — alors que le fondu la
    /// concerne autant que l'autre.
    func updateEdgeFade(zoomScale: CGFloat, displayScale: CGFloat, viewportSize: CGSize) {
        let scale = max(displayScale, 1)
        if fadeImageScale != scale {
            fadeImageScale = scale
            let pixels = MapEdgeFadeImage.bandPixels(displayScale: scale)
            fadeLayer.contents = MapEdgeFadeImage.make(bandPixels: pixels, color: NCColor.nightSkyRGBA)
            fadeLayer.contentsCenter = MapEdgeFadeImage.contentsCenter(bandPixels: pixels)
        }
        let fade = MapGeometry.edgeFade(
            band: MapEdgeFadeImage.band,
            contentSize: CGSize(width: contentSize, height: contentSize),
            zoomScale: zoomScale,
            displayScale: scale,
            in: viewportSize
        )
        fadeLayer.contentsScale = fade.contentsScale
        fadeLayer.opacity = fade.opacity
    }
```

- [ ] **Step 4 : brancher dans `sync` et changer le fond**

Dans `NeonCompass/Core/Map/MapScrollView.swift`, remplacer :

```swift
        scrollView.backgroundColor = .black
```

par :

```swift
        // Le fond de l'app, et non du noir : le fondu des bords éteint la
        // carte sur cette teinte-là, donc c'est elle qui doit se trouver
        // derrière. Le noir suffisait tant que le bord était une découpe —
        // mesuré, il en était à 393 d'écart cumulé sur trois canaux au pire
        // des quatre habillages.
        scrollView.backgroundColor = UIColor(NCColor.nightSky)
```

Et dans `sync(_:)`, juste AVANT l'appel `tileLayerView?.update(` :

```swift
            // Avant `update`, et non dedans : celui-ci rend la main tout de
            // suite quand la carte n'a pas de pyramide, et le fondu la concerne
            // aussi.
            tileLayerView?.updateEdgeFade(
                zoomScale: newViewport.zoomScale,
                displayScale: scrollView.traitCollection.displayScale,
                viewportSize: scrollView.bounds.size
            )
```

- [ ] **Step 5 : construire et lancer la suite complète**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test > /tmp/t4.log 2>&1 &
```
Attendre `Test run with`, lire le compte et les échecs, `pkill -f xcodebuild`. Attendu : zéro échec.

- [ ] **Step 6 : vérifier qu'aucun artefact n'est emporté**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git status --short
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
```

- [ ] **Step 7 : commit**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git add NeonCompass/Core/Map/MapTileLayerView.swift NeonCompass/Core/Map/MapScrollView.swift
git commit -F /tmp/msg-t4.txt
```

`/tmp/msg-t4.txt` :

```
feat(carte): les bords de la carte s'eteignent au lieu d'etre coupes

Un calque entre les tuiles et les epingles — celles-ci vivent dans une autre
vue du meme conteneur, donc elles restent nettes sans qu'on ait rien a
faire. zPosition et non l'ordre d'insertion : les tuiles s'ajoutent apres
coup.

Le fondu se pose hors de update(visibleContentRect:), qui rend la main tout
de suite quand la carte n'a pas de pyramide — soit la carte de reference,
celle sur laquelle l'app ouvre.

Le fond du defilement passe au fond de l'app : c'est la teinte sur laquelle
le fondu eteint la carte.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

---

### Task 5 : la recette au simulateur

**Files:**
- Aucun fichier du dépôt n'est modifié par cette tâche. L'instrumentation ci-dessous est **temporaire et ne doit JAMAIS être commitée** — elle est retirée à l'avant-dernière étape, et la dernière vérifie que l'arbre est propre.

**Ce que la tâche prouve, et que rien d'autre ne prouve :** que le plafond posé sur l'appareil vaut bien 4,95 sur iPad et 3,3 sur iPhone (les tâches 1-2 ne le prouvent que sur des nombres), et que l'écart de couleur au bord de la carte est retombé sous 12 sur les quatre habillages, contre 393 aujourd'hui au pire.

**Contraintes d'automatisation :** l'écran du Mac est verrouillé, donc `cliclick` est inopérant et aucun geste réel n'est rejouable. C'est pourquoi le zoom et la position sont posés par variables d'environnement. `xcrun simctl` uniquement — ni `osascript`, ni AppleScript, ni « System Events », ni `screencapture`, qui atteindraient le vrai bureau.

- [ ] **Step 1 : appliquer l'instrumentation temporaire**

**(a)** Dans `NeonCompass/Core/Map/MapScrollView.swift`, à la fin de `FitToBoundsScrollView.layoutSubviews()`, après le bloc `if !hasPerformedInitialFit { … } else { … }` et avant l'accolade fermante de la méthode :

```swift
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["NC_MAP_DEBUG"] {
            let p = raw.split(separator: ",").compactMap { Double($0) }
            if p.count == 3 {
                print("NC_RECETTE maximumZoomScale=\(maximumZoomScale) displayScale=\(traitCollection.displayScale) bounds=\(bounds.size)")
                zoomScale = CGFloat(p[0]) * maximumZoomScale
                let i = MapGeometry.centeringInsets(contentSize: contentNativeSize, zoomScale: zoomScale, in: bounds.size)
                contentInset = UIEdgeInsets(top: i.top, left: i.left, bottom: i.bottom, right: i.right)
                contentOffset = CGPoint(
                    x: CGFloat(p[1]) * contentNativeSize.width * zoomScale - bounds.width / 2,
                    y: CGFloat(p[2]) * contentNativeSize.height * zoomScale - bounds.height / 2
                )
            }
        }
        #endif
```

**(b)** Dans `NeonCompass/App/AppModel.swift`, à la fin de `init(defaults:)` :

```swift
        #if DEBUG
        if ProcessInfo.processInfo.environment["NC_MAP_TAB"] != nil {
            selectedTab = .map
            // `requestedMapGame` est le chemin qui existe déjà — `MapScreen`
            // le consomme dans un `.onChange(initial: true)`, donc le poser
            // ici suffit. Rien à greffer sur son `@State`.
            if ProcessInfo.processInfo.environment["NC_MAP_GAME"] == "vi" { requestedMapGame = .leonida }
        }
        #endif
```

**(c)** Dans `NeonCompass/Features/Map/MapScreen.swift`, remplacer la ligne `@State private var mapStyle: MapStyle = .neon` (ligne 36, sous son commentaire, qu'on laisse en place) par :

```swift
    @State private var mapStyle: MapStyle =
        ProcessInfo.processInfo.environment["NC_MAP_STYLE"] == "classic" ? .classic : .neon
```

**(d)** Dans `NeonCompass/Core/Map/MapTileLayerView.swift`, en PREMIÈRE ligne du corps de `updateEdgeFade(zoomScale:displayScale:viewportSize:)` :

```swift
        #if DEBUG
        // Sert à prouver que la mesure sait échouer : sans fondu, elle doit
        // retrouver les écarts mesurés avant le chantier.
        if ProcessInfo.processInfo.environment["NC_MAP_NO_FADE"] != nil { fadeLayer.opacity = 0; return }
        #endif
```

- [ ] **Step 2 : construire et installer sur l'iPad**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
xcrun simctl boot BD8F6F17-90B0-42CD-BE05-10866A1BE21D 2>/dev/null || true
PAD='platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
xcodebuild -scheme NeonCompass -destination "$PAD" build > /tmp/b-ipad.log 2>&1
BUILT=$(xcodebuild -scheme NeonCompass -destination "$PAD" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
echo "BUILT=$BUILT"
rm -rf "$BUILT/NeonCompass.app/MapArt" "$BUILT/NeonCompass.app/MapTiles"
xcodebuild -scheme NeonCompass -destination "$PAD" build > /tmp/b-ipad2.log 2>&1
xcrun simctl install BD8F6F17-90B0-42CD-BE05-10866A1BE21D "$BUILT/NeonCompass.app"
```

L'effacement puis la reconstruction ne sont pas superflus : une ressource `type: folder` n'est pas recopiée quand son contenu change, et une pyramide périmée ne se voit pas — la carte s'affiche, simplement avec les pixels d'avant. `BUILT_PRODUCTS_DIR` vient de `-showBuildSettings` ; un glob dans DerivedData rendrait un autre répertoire.

- [ ] **Step 3 : lire les quatre plafonds réellement posés**

```bash
run_ipad () {  # $1=game $2=style $3=debug-triplet
  xcrun simctl terminate BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass 2>/dev/null || true
  env SIMCTL_CHILD_NC_MAP_TAB=1 SIMCTL_CHILD_NC_MAP_GAME="$1" SIMCTL_CHILD_NC_MAP_STYLE="$2" \
      SIMCTL_CHILD_NC_MAP_DEBUG="$3" \
    xcrun simctl launch --console-pty BD8F6F17-90B0-42CD-BE05-10866A1BE21D \
    co.antoineteston.NeonCompass > /tmp/console-$1-$2.txt 2>&1 &
  sleep 6
  pkill -f "simctl launch" 2>/dev/null || true
  grep NC_RECETTE /tmp/console-$1-$2.txt | tail -1
}
run_ipad vi neon "1.0,0.0,0.0"
run_ipad reference neon "1.0,0.0,0.0"
```

Attendu sur iPad (×2) : `maximumZoomScale=4.95` pour la carte pyramidée, `maximumZoomScale=3.75` pour la carte de référence.

Puis les deux mêmes sur iPhone 17, après construction et installation pour cette destination (mêmes commandes que l'étape 2 avec `platform=iOS Simulator,name=iPhone 17` et l'identifiant `BD68054B-7C1F-48C8-B792-AB2C87C4B7A3`). Attendu : `3.3` et `2.5`.

**Un nombre différent vaut échec de la tâche 2, pas de celle-ci** — le rapporter tel quel plutôt que d'ajuster quoi que ce soit ici.

- [ ] **Step 4 : capturer les quatre habillages au coin, fondu actif**

Le triplet `1.0,0.0,0.0` pose le zoom au plafond et amène le coin haut-gauche de la carte au CENTRE de l'écran — c'est la frontière qu'on vient mesurer, et sa position est donc connue d'avance plutôt que cherchée.

```bash
for GAME in vi reference; do for STYLE in neon classic; do
  xcrun simctl terminate BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass 2>/dev/null || true
  env SIMCTL_CHILD_NC_MAP_TAB=1 SIMCTL_CHILD_NC_MAP_GAME=$GAME SIMCTL_CHILD_NC_MAP_STYLE=$STYLE \
      SIMCTL_CHILD_NC_MAP_DEBUG="1.0,0.0,0.0" \
    xcrun simctl launch BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass
  sleep 5
  xcrun simctl io BD8F6F17-90B0-42CD-BE05-10866A1BE21D screenshot /tmp/recette-$GAME-$STYLE.png
done; done
```

Regarder `/tmp/recette-vi-neon.png` avec l'outil Read avant de mesurer quoi que ce soit : à 4,95 sur iPad, les libellés de rue doivent être **lisibles**. C'est le critère visuel de la tâche 2, et il ne se remplace pas par un nombre.

- [ ] **Step 5 : écrire l'outil de mesure**

Écrire `/tmp/mesure-bord.py` avec l'outil Write :

```python
"""Ecart de couleur maximal entre deux pixels voisins, en traversant le bord
gauche de la carte. Le coin haut-gauche est au centre exact de l'ecran, donc
la frontiere se trouve a la moitie de la largeur de la capture."""
import struct, subprocess, sys, tempfile, os

def read_bmp(path):
    raw = open(path, 'rb').read()
    offset, = struct.unpack_from('<I', raw, 10)
    width, height = struct.unpack_from('<ii', raw, 18)
    bpp, = struct.unpack_from('<H', raw, 28)
    assert bpp in (24, 32), bpp
    step = bpp // 8
    stride = ((width * bpp + 31) // 32) * 4
    bottom_up = height > 0
    height = abs(height)
    def pixel(x, y):
        row = (height - 1 - y) if bottom_up else y
        i = offset + row * stride + x * step
        return raw[i + 2], raw[i + 1], raw[i]   # BMP stocke en BGR
    return width, height, pixel

path = sys.argv[1]
offset_rows = int(sys.argv[2]) if len(sys.argv) > 2 else 200
bmp = os.path.join(tempfile.gettempdir(), os.path.basename(path) + '.bmp')
subprocess.run(['sips', '-s', 'format', 'bmp', path, '--out', bmp],
               check=True, capture_output=True)
w, h, pixel = read_bmp(bmp)
y = h // 2 + offset_rows
worst, where, prev = 0, 0, None
for x in range(max(0, w // 2 - 260), min(w, w // 2 + 260)):
    px = pixel(x, y)
    if prev is not None:
        d = sum(abs(px[i] - prev[i]) for i in range(3))
        if d > worst:
            worst, where = d, x
    prev = px
print(f"{os.path.basename(path)}: ecart max {worst} a x={where} (ligne y={y}, centre x={w//2})")
```

`sips` fait le décodage — il est présent sur toute installation de macOS, là où un lecteur de PNG écrit à la main mettrait une minute par capture et supposerait un type de couleur.

- [ ] **Step 6 : prouver que la mesure sait échouer**

Recapturer les quatre habillages avec `SIMCTL_CHILD_NC_MAP_NO_FADE=1` ajouté à la ligne `env` de l'étape 4, vers `/tmp/sansfondu-$GAME-$STYLE.png`, et mesurer :

```bash
for f in /tmp/sansfondu-*.png; do /usr/bin/python3 /tmp/mesure-bord.py "$f"; done
```

Attendu, à quelques unités près, la **quatrième** colonne du tableau de la spec — celle du fond `nightSky`, puisque la tâche 4 a déjà changé le fond :

| capture | écart attendu sans fondu |
|---|---|
| `reference-neon` (V néon) | ≈ 1 |
| `reference-classic` (V classique) | ≈ 349 |
| `vi-neon` | ≈ 43 |
| `vi-classic` | ≈ 267 |

Cette étape fait deux choses d'un coup : elle prouve que la mesure sait rapporter un écart quand il y en a un — un contrôle qui ne sait qu'approuver est indiscernable d'un bon — et elle recoupe les mesures sur lesquelles la spec est bâtie. Si les quatre nombres sont loin de ces attendus, c'est la mesure qui est fausse, pas le correctif : le dire dans le rapport plutôt que d'ajuster le seuil.

- [ ] **Step 7 : mesurer avec le fondu**

```bash
for f in /tmp/recette-*.png; do /usr/bin/python3 /tmp/mesure-bord.py "$f"; done
```

**Critère de recette : aucun écart supérieur à 12 sur les quatre habillages.** Si une ligne dépasse, ouvrir la capture : un écart peut venir d'un détail INTERNE de la carte — une route, un liseré — qui traverse la ligne de coupe. Dans ce cas relancer avec un autre décalage (`python3 /tmp/mesure-bord.py <capture> 400`) et le dire dans le rapport. Un écart situé au voisinage immédiat de `x = centre`, lui, est un vrai échec.

- [ ] **Step 8 : vérifier qu'il n'y a pas de fondu au repos**

C'est le point sur lequel ce plan corrige la spec, et le seul qui ne se lit pas dans un nombre : au repos la carte affleure exactement deux bords de l'écran, donc un fondu mal conditionné y poserait une vignette de 80 pt en haut et en bas.

```bash
xcrun simctl terminate BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass 2>/dev/null || true
env SIMCTL_CHILD_NC_MAP_TAB=1 SIMCTL_CHILD_NC_MAP_GAME=vi SIMCTL_CHILD_NC_MAP_STYLE=neon \
  xcrun simctl launch BD8F6F17-90B0-42CD-BE05-10866A1BE21D co.antoineteston.NeonCompass
sleep 5
xcrun simctl io BD8F6F17-90B0-42CD-BE05-10866A1BE21D screenshot /tmp/recette-repos.png
```

Ouvrir la capture avec l'outil Read. Aucun assombrissement ne doit border le haut ni le bas de l'écran.

- [ ] **Step 9 : retirer l'instrumentation**

```bash
cd /Users/antoine/gta_project/.claude/worktrees/carte-fondu-plafond
git checkout -- NeonCompass/Core/Map/MapScrollView.swift NeonCompass/App/AppModel.swift \
                NeonCompass/Features/Map/MapScreen.swift NeonCompass/Core/Map/MapTileLayerView.swift
git status --short
```

`git status --short` doit ne RIEN rendre. **Aucun commit dans cette tâche** : elle ne produit que des mesures.

- [ ] **Step 10 : consigner**

Le rapport porte, en clair : les quatre plafonds lus (`4.95` / `3.75` sur iPad, `3.3` / `2.5` sur iPhone), les quatre écarts sans fondu, les quatre écarts avec fondu et le pire d'entre eux, le décalage de ligne utilisé s'il a fallu le changer, et le verdict sur la lisibilité des libellés à 4,95.

---

## Ce que ce plan ne fait pas

- **Le centrage n'est pas touché.** `MapGeometry.centeringInsets` pose déjà le plancher d'une demi-fenêtre au-delà de l'échelle de couverture, et c'est ce débord qui rend le coin atteignable — donc ce qui a RÉVÉLÉ la découpe franche, pas ce qui la cause.
- **Les PNG ne sont pas régénérés.** Le fondu est un calque, à l'exécution.
- **Aucun réglage de coloris.** La spec en note les deux leviers — la palette du classificateur en amont, une courbe au décodage à l'exécution — et les laisse hors sujet. Un piège à retenir si la question revient : `CALayer.filters` existe dans l'API mais n'est PAS appliqué sur iOS, seulement sur macOS.
- **L'orientation paysage n'est pas vérifiée** : `simctl` n'a pas de commande de rotation, et l'écran du Mac est verrouillé. La formule du plafond n'en dépend pas ; l'opacité du fondu, si — en paysage c'est la LARGEUR qui affleure. Le minimum sur les deux axes traite le cas sans le distinguer, mais il n'est pas mesuré.
- **Le rabot du zoom courant n'est exercé par rien**, ni test ni recette, et il faut le dire plutôt que le laisser croire couvert. Ses deux chemins sont hors d'atteinte ici : celui du changement de CARTE est précédé de `refit()`, qui a déjà ramené le zoom au repos — le rabot y est prouvé redondant, donc l'exercer ne prouverait rien ; celui du changement d'ÉCHELLE D'AFFICHAGE demande un écran externe ou Stage Manager, qu'un simulateur piloté par `simctl` sur un Mac verrouillé ne sait pas produire. Le rabot est un filet pour un chemin qu'on ne sait pas parcourir, et c'est exactement pourquoi il est là.
