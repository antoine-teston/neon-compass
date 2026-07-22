# Plan 3 — Contenu & sync : infrastructure (Neon Compass v1.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le fixture POI bundlé du plan 2 par un vrai pipeline Firestore → cache SwiftData local, versionné par Remote Config, avec un CLI admin capable de pousser du contenu réel — sans jamais faire dépendre le code app d'un projet Firebase vivant pour compiler ou être testé.

**Architecture :** Toute la surface Firebase est cachée derrière deux protocoles dans `Core/Content/` (`ContentVersionProviding`, `POIRemoteRepository`) — les tests unitaires utilisent des implémentations `Fake*` en mémoire, jamais le SDK réel. Les 5 premières tâches sont donc buildables et testables sans aucun projet Firebase existant. Seules les 2 dernières tâches (extension CLI vers un vrai push, wiring `FirebaseApp.configure()`) nécessitent un projet Firebase réel — elles sont explicitement isolées en fin de plan.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + `@Observable`, SwiftData, Firebase iOS SDK (Firestore, Remote Config) via SPM, Swift Testing.

**Prérequis externe (bloquant seulement pour les Tasks 6-7) :** un projet Firebase (console.firebase.google.com), plan Spark (gratuit) suffisant pour Firestore + Remote Config à ce stade, avec `GoogleService-Info.plist` téléchargé.

## Global Constraints

- Cible : iOS/iPadOS 26.0 minimum, iPhone + iPad, pas de Mac Catalyst.
- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.
- Firebase isolé derrière des protocoles dans `Core/` — les features ne l'importent jamais directement (spec §3, CLAUDE.md).
- Contenu éditorial : Firestore → cache SwiftData local ; lecture réseau en delta piloté par `contentVersion` (Remote Config) ; app pleinement utilisable hors-ligne (spec §3).
- Aucune marque Rockstar dans le code, les identifiants, les strings ou les assets.
- Tests : Swift Testing (`import Testing`), jamais XCTest.
- Commandes de vérification : `Scripts/test.sh`, `Scripts/build.sh`.

---

### Task 1: Dépendance Firebase (SPM) + scaffolding `Core/Content/`

**Files:**
- Modify: `project.yml`
- Create: `NeonCompass/Core/Content/ContentVersionProviding.swift`, `NeonCompass/Core/Content/POIRemoteRepository.swift`

**Interfaces:**
- Produces: `protocol ContentVersionProviding: Sendable { func currentVersion() -> Int }` ; `protocol POIRemoteRepository: Sendable { func fetchAll() async throws -> [POI] }`. Consommé par Task 3 (implémentations Fake) et Task 4 (`POIContentStore`).

- [ ] **Step 1: Ajouter la dépendance SPM Firebase dans `project.yml`**

Sous la clé racine (au même niveau que `targets`), ajouter :
```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    from: 11.0.0
```
Et dans `targets.NeonCompass`, ajouter une clé `dependencies` :
```yaml
    dependencies:
      - package: Firebase
        product: FirebaseFirestore
      - package: Firebase
        product: FirebaseRemoteConfig
```
Note : la version exacte (`from: 11.0.0`) peut nécessiter un ajustement si SPM résout une version différente au moment de l'exécution — l'important est que le package résolve et que les deux produits soient disponibles. Si `xcodegen generate` échoue sur la résolution SPM, vérifier la connectivité réseau avant d'ajuster la contrainte de version.

- [ ] **Step 2: Vérifier que le projet build avec la dépendance ajoutée (sans encore l'utiliser)**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **` (la résolution SPM peut prendre plusieurs minutes au premier run — le SDK Firebase est volumineux). Aucun `import Firebase*` n'existe encore dans le code, donc ce step valide uniquement que la dépendance est correctement déclarée et résolue.

- [ ] **Step 3: Créer les protocoles**

`NeonCompass/Core/Content/ContentVersionProviding.swift` :
```swift
import Foundation

/// Abstraction sur Remote Config — permet de tester le versionnement de
/// contenu sans dépendre du SDK Firebase (spec §3 : "Firebase isolé derrière
/// des protocoles dans Core/").
protocol ContentVersionProviding: Sendable {
    func currentVersion() -> Int
}
```

`NeonCompass/Core/Content/POIRemoteRepository.swift` :
```swift
import Foundation

/// Abstraction sur la source distante des POI (Firestore en production).
protocol POIRemoteRepository: Sendable {
    func fetchAll() async throws -> [POI]
}
```

- [ ] **Step 4: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add project.yml NeonCompass/Core/Content
git commit -m "feat: add Firebase SPM dependency + Core/Content protocol scaffolding"
```

---

### Task 2: `FirestorePOIRepository` — implémentation réelle (compile sans projet vivant)

**Files:**
- Create: `NeonCompass/Core/Content/FirestorePOIRepository.swift`

**Interfaces:**
- Consumes: `POIRemoteRepository` (Task 1), `POI`/`POICategory`/`NormalizedPoint`/`LocalizedText` (Plan 2 Task 2).
- Produces: `final class FirestorePOIRepository: POIRemoteRepository`. Consommé par Task 7 (wiring réel).

Pas de test unitaire sur cette tâche : le SDK Firestore ne peut être exercé qu'avec un projet réel (Task 7). Vérification par build uniquement — le SPM package résolu à la Task 1 permet à `import FirebaseFirestore` de compiler sans qu'aucun projet ne soit configuré (`FirebaseApp.configure()` n'est appelé nulle part ici).

- [ ] **Step 1: Implémenter**

`NeonCompass/Core/Content/FirestorePOIRepository.swift` :
```swift
import FirebaseFirestore

/// Implémentation réelle de POIRemoteRepository. Ne référence jamais
/// FirebaseApp.configure() — la configuration de l'app reste centralisée
/// au niveau App (Task 7), cette classe ne fait qu'utiliser Firestore.firestore()
/// une fois l'app configurée.
///
/// v1 : synchronisation par collection entière (pas de delta par document) —
/// suffisant tant que le nombre de POI reste modeste ; à optimiser en delta
/// document-par-document si le contenu grossit significativement.
final class FirestorePOIRepository: POIRemoteRepository {
    private let collection: CollectionReference

    init(firestore: Firestore = Firestore.firestore()) {
        collection = firestore.collection("poi")
    }

    func fetchAll() async throws -> [POI] {
        let snapshot = try await collection.getDocuments()
        return try snapshot.documents.compactMap { document in
            let data = try JSONSerialization.data(withJSONObject: document.data())
            return try JSONDecoder().decode(POI.self, from: data)
        }
    }
}
```

Note d'implémentation : si l'API Firestore Codable native (`document.data(as:)`) est disponible et plus idiomatique dans la version du SDK réellement résolue par SPM, l'utiliser à la place du pont `JSONSerialization` manuel ci-dessus — l'important est que le comportement (décoder chaque document Firestore en `POI` en tolérant les champs additionnels, cohérent avec le décodage `Codable` déjà utilisé au plan 2) soit préservé. Ajuster minimalement si la syntaxe exacte diffère, sans changer le contrat de `POIRemoteRepository`.

- [ ] **Step 2: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add NeonCompass/Core/Content/FirestorePOIRepository.swift
git commit -m "feat: FirestorePOIRepository — real Firestore-backed POI fetch"
```

---

### Task 3: Fakes de test + `RemoteConfigVersionProvider`

**Files:**
- Create: `NeonCompass/Core/Content/RemoteConfigVersionProvider.swift`
- Test: `NeonCompassTests/Content/FakesTests.swift`

**Interfaces:**
- Consumes: `ContentVersionProviding`, `POIRemoteRepository` (Task 1).
- Produces: `final class RemoteConfigVersionProvider: ContentVersionProviding` (réel, `import FirebaseRemoteConfig`) ; dans le fichier de test : `final class FakeContentVersionProvider: ContentVersionProviding` (`var version: Int = 0`) et `final class FakePOIRemoteRepository: POIRemoteRepository` (`var poisToReturn: [POI] = []`, `var fetchCallCount = 0`). Ces deux fakes sont consommés par Task 4 (`POIContentStoreTests`).

Cette tâche a deux parties distinctes : les fakes (testables, écrits en un seul step — fakes et tests s'ajoutent ensemble dans un nouveau fichier, sans état RED intermédiaire significatif à observer, à la différence des tâches modifiant un fichier existant) et `RemoteConfigVersionProvider` (implémentation réelle adossée au SDK Firebase — comme `FirestorePOIRepository` à la Task 2, pas de test unitaire possible sans projet vivant, vérification par build uniquement).

**Partie A — Fakes**

- [ ] **Step 1: Écrire les fakes et leurs tests**

`NeonCompassTests/Content/FakesTests.swift` :
```swift
import Testing
@testable import NeonCompass

final class FakeContentVersionProvider: ContentVersionProviding {
    var version: Int = 0
    func currentVersion() -> Int { version }
}

final class FakePOIRemoteRepository: POIRemoteRepository {
    var poisToReturn: [POI] = []
    private(set) var fetchCallCount = 0

    func fetchAll() async throws -> [POI] {
        fetchCallCount += 1
        return poisToReturn
    }
}

struct FakesTests {
    @Test func versionProviderReturnsSetValue() {
        let fake = FakeContentVersionProvider()
        fake.version = 5
        #expect(fake.currentVersion() == 5)
    }

    @Test func remoteRepositoryTracksFetchCallsAndReturnsSetPOIs() async throws {
        let fake = FakePOIRemoteRepository()
        let poi = POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                      title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
        fake.poisToReturn = [poi]
        let result = try await fake.fetchAll()
        #expect(result == [poi])
        #expect(fake.fetchCallCount == 1)
    }
}
```

Les deux fakes implémentent des protocoles déjà présents depuis la Task 1 (`ContentVersionProviding`, `POIRemoteRepository`).

- [ ] **Step 2: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

**Partie B — Implémentation réelle (build-only, comme `FirestorePOIRepository` à la Task 2)**

- [ ] **Step 3: Implémenter `RemoteConfigVersionProvider`**

`NeonCompass/Core/Content/RemoteConfigVersionProvider.swift` :
```swift
import FirebaseRemoteConfig

/// Implémentation réelle de ContentVersionProviding, adossée à Firebase
/// Remote Config. Ne configure jamais FirebaseApp elle-même (Task 7).
final class RemoteConfigVersionProvider: ContentVersionProviding {
    private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = RemoteConfig.remoteConfig()) {
        self.remoteConfig = remoteConfig
    }

    func currentVersion() -> Int {
        Int(remoteConfig.configValue(forKey: "contentVersion").numberValue?.intValue ?? 0)
    }
}
```

Note d'implémentation : ajuster la syntaxe d'accès à la valeur (`configValue(forKey:).numberValue`) si l'API du SDK réellement résolu diffère légèrement — le contrat (`currentVersion() -> Int`, robuste à une clé absente en retournant `0`) doit être préservé.

- [ ] **Step 4: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Content/RemoteConfigVersionProvider.swift NeonCompassTests/Content/FakesTests.swift
git commit -m "feat: RemoteConfigVersionProvider + test fakes for content sync"
```

---

### Task 4: `POIContentStore` — SwiftData cache + logique de version-gate

**Files:**
- Create: `NeonCompass/Core/Content/POICacheEntry.swift`, `NeonCompass/Core/Content/POIContentStore.swift`
- Test: `NeonCompassTests/Content/POIContentStoreTests.swift`

**Interfaces:**
- Consumes: `POI`, `POIRemoteRepository`, `ContentVersionProviding` (Tasks 1-3), `FakeContentVersionProvider`/`FakePOIRemoteRepository` (Task 3, réutilisés depuis le fichier de test partagé).
- Produces: `@Model final class POICacheEntry` (`@Attribute(.unique) var collectionName: String`, `var json: Data`, `var version: Int`) ; `@Observable @MainActor final class POIContentStore` (`init(remote: POIRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext)`, `private(set) var pois: [POI]` (chargé depuis le cache à l'initialisation), `func syncIfNeeded() async throws`). Consommé par Task 5 (`MapScreen`).

- [ ] **Step 1: Écrire les tests (failing)**

`NeonCompassTests/Content/POIContentStoreTests.swift` :
```swift
import Testing
import SwiftData
@testable import NeonCompass

@MainActor
struct POIContentStoreTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([POICacheEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOI(id: String) -> POI {
        POI(id: id, category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
            title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil)
    }

    @Test func startsEmptyWithNoCacheAndVersionZero() {
        let remote = FakePOIRemoteRepository()
        let version = FakeContentVersionProvider()
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: makeContext())
        #expect(store.pois.isEmpty)
    }

    @Test func syncFetchesAndCachesWhenRemoteVersionIsNewer() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: makeContext())

        try await store.syncIfNeeded()

        #expect(store.pois.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }

    @Test func syncIsNoOpWhenVersionUnchanged() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()
        let store = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await store.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)

        // Un second store réutilisant le même contexte (donc le même cache
        // persisté) avec une version distante inchangée ne doit pas re-fetcher.
        let secondStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await secondStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)
    }

    @Test func loadsFromCacheOnInitWithoutNetworkCall() async throws {
        let remote = FakePOIRemoteRepository()
        remote.poisToReturn = [samplePOI(id: "a")]
        let version = FakeContentVersionProvider()
        version.version = 1
        let context = makeContext()

        let firstStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        try await firstStore.syncIfNeeded()
        #expect(remote.fetchCallCount == 1)

        // Un nouveau store sur le même contexte doit charger depuis le cache
        // dès l'init, sans appel réseau — l'app doit être utilisable hors-ligne.
        let secondStore = POIContentStore(remote: remote, versionProvider: version, modelContext: context)
        #expect(secondStore.pois.map(\.id) == ["a"])
        #expect(remote.fetchCallCount == 1)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `Scripts/test.sh`
Expected: BUILD FAILED — `cannot find 'POIContentStore' in scope`

- [ ] **Step 3: Implémenter**

`NeonCompass/Core/Content/POICacheEntry.swift` :
```swift
import Foundation
import SwiftData

/// Cache SwiftData d'une collection de contenu entière, sérialisée en JSON.
/// v1 : granularité "toute la collection" (pas de delta par document) —
/// suffisant tant que le volume de contenu reste modeste (spec §7 : le
/// pipeline de contenu vise des dizaines à quelques centaines d'entrées).
@Model
final class POICacheEntry {
    @Attribute(.unique) var collectionName: String
    var json: Data
    var version: Int

    init(collectionName: String, json: Data, version: Int) {
        self.collectionName = collectionName
        self.json = json
        self.version = version
    }
}
```

`NeonCompass/Core/Content/POIContentStore.swift` :
```swift
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class POIContentStore {
    private static let collectionName = "poi"

    private(set) var pois: [POI]

    private let remote: POIRemoteRepository
    private let versionProvider: ContentVersionProviding
    private let modelContext: ModelContext

    init(remote: POIRemoteRepository, versionProvider: ContentVersionProviding, modelContext: ModelContext) {
        self.remote = remote
        self.versionProvider = versionProvider
        self.modelContext = modelContext
        self.pois = Self.loadCached(from: modelContext)
    }

    func syncIfNeeded() async throws {
        let remoteVersion = versionProvider.currentVersion()
        let localVersion = Self.cachedVersion(from: modelContext)
        guard remoteVersion > localVersion else { return }

        let fetched = try await remote.fetchAll()
        let data = try JSONEncoder().encode(fetched)

        let name = Self.collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.json = data
            existing.version = remoteVersion
        } else {
            modelContext.insert(POICacheEntry(collectionName: Self.collectionName, json: data, version: remoteVersion))
        }
        try modelContext.save()

        pois = fetched
    }

    private static func loadCached(from modelContext: ModelContext) -> [POI] {
        let name = collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        guard let entry = try? modelContext.fetch(descriptor).first,
              let decoded = try? JSONDecoder().decode([POI].self, from: entry.json) else {
            return []
        }
        return decoded
    }

    private static func cachedVersion(from modelContext: ModelContext) -> Int {
        let name = collectionName
        let descriptor = FetchDescriptor<POICacheEntry>(
            predicate: #Predicate { $0.collectionName == name }
        )
        return (try? modelContext.fetch(descriptor).first?.version) ?? 0
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: `Scripts/test.sh`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Content/POICacheEntry.swift NeonCompass/Core/Content/POIContentStore.swift NeonCompassTests/Content/POIContentStoreTests.swift
git commit -m "feat: POIContentStore — SwiftData cache + version-gated sync"
```

---

### Task 5: Wiring dans `MapScreen` — remplacement du fixture bundlé

**Files:**
- Modify: `NeonCompass/Features/Map/MapScreen.swift`
- Modify: `NeonCompass/App/NeonCompassApp.swift`

**Interfaces:**
- Consumes: `POIContentStore` (Task 4), `FirestorePOIRepository` (Task 2), `RemoteConfigVersionProvider` (Task 3), `MapModel` (Plan 2 Task 3).
- Produces: `MapScreen` chargé désormais via `POIContentStore` plutôt que `POILoader.loadSeed()`.

Pas de test unitaire — assemblage de vues déjà couvert par les tests de `POIContentStore` (Task 4) et de `MapModel` (Plan 2 Task 3). Vérification par build + vérification visuelle.

- [ ] **Step 1: Modifier `MapScreen` pour consommer `POIContentStore`**

Dans `NeonCompass/Features/Map/MapScreen.swift`, remplacer :
```swift
    private func loadModel() {
        guard model == nil else { return }
        let pois = (try? POILoader.loadSeed()) ?? []
        model = MapModel(pois: pois, modelContext: modelContext)
    }
```
par :
```swift
    private func loadModel() {
        guard model == nil else { return }
        let contentStore = POIContentStore(
            remote: FirestorePOIRepository(),
            versionProvider: RemoteConfigVersionProvider(),
            modelContext: modelContext
        )
        model = MapModel(pois: contentStore.pois, modelContext: modelContext)
        Task {
            try? await contentStore.syncIfNeeded()
            model?.updatePOIs(contentStore.pois)
        }
    }
```

Ceci introduit une nouvelle méthode sur `MapModel` (plan 2, actuellement `private(set) var pois: [POI]` sans mutateur public) — l'ajouter :

Dans `NeonCompass/Features/Map/MapModel.swift`, ajouter à la classe `MapModel` :
```swift
    func updatePOIs(_ newPOIs: [POI]) {
        pois = newPOIs
    }
}
```

- [ ] **Step 2: Vérifier le build**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

Note : sans `GoogleService-Info.plist` réel (Task 7 non faite), `FirestorePOIRepository`/`RemoteConfigVersionProvider` compileront et s'instancieront, mais tout appel réseau réel échouera silencieusement (`syncIfNeeded()` catch l'erreur via `try?` dans le code ci-dessus) — l'app reste utilisable avec un cache vide jusqu'à ce que la Task 7 câble un vrai projet. C'est le comportement attendu et conforme à "l'app est pleinement utilisable hors-ligne" : sans réseau/projet configuré, elle affiche simplement une carte sans POI plutôt que de crasher.

- [ ] **Step 3: Vérification visuelle simulateur**

Lancer l'app (iPhone et iPad) : l'onglet Carte doit s'afficher normalement (viewer tuilé, filtres) sans POI visible (cache vide, sync échoue silencieusement sans projet Firebase configuré) — pas de crash, pas de blocage. C'est le comportement attendu à ce stade du plan ; les POI reviendront visibles une fois la Task 7 câblée avec un vrai projet et du contenu poussé par le CLI (Task 6).

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Map/MapScreen.swift NeonCompass/Features/Map/MapModel.swift
git commit -m "feat: wire MapScreen to POIContentStore, replacing bundled fixture"
```

---

### Task 6: CLI admin — push réel vers Firestore

**Files:**
- Modify: `tools/content-cli/cli.js`
- Create: `tools/content-cli/firestore-client.js`

**Interfaces:**
- Produces: `publish` (sans `--dry-run`) pousse réellement vers Firestore via `firebase-admin`, puis incrémente `contentVersion` dans Remote Config.

**⚠️ Cette tâche nécessite un projet Firebase réel et une clé de compte de service (service account JSON) — voir prérequis en tête de plan. Ne pas commencer avant que l'utilisateur ait fourni ces éléments.**

- [ ] **Step 1: Installer `firebase-admin`**

Run (depuis `tools/content-cli/`) : `npm install firebase-admin`

- [ ] **Step 2: Implémenter le client Firestore admin**

`tools/content-cli/firestore-client.js` :
```javascript
// Pont vers Firestore via firebase-admin — n'est importé que par la commande
// `publish` (jamais par validate/check-publishable/translate, qui restent
// utilisables sans credentials). La clé de compte de service est lue depuis
// la variable d'environnement FIREBASE_SERVICE_ACCOUNT_PATH, jamais committée.

import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getRemoteConfig } from 'firebase-admin/remote-config';

let appInstance = null;

function app() {
  if (appInstance) return appInstance;
  const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (!keyPath) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_PATH env var not set — cannot publish without credentials');
  }
  const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
  appInstance = initializeApp({ credential: cert(serviceAccount) });
  return appInstance;
}

export async function pushDocuments(collectionName, documents) {
  const db = getFirestore(app());
  const batch = db.batch();
  for (const doc of documents) {
    batch.set(db.collection(collectionName).doc(doc.id), doc);
  }
  await batch.commit();
}

export async function incrementContentVersion() {
  const rc = getRemoteConfig(app());
  const template = await rc.getTemplate();
  const current = Number(template.parameters.contentVersion?.defaultValue?.value ?? '0');
  template.parameters.contentVersion = {
    defaultValue: { value: String(current + 1) },
  };
  await rc.publishTemplate(template);
  return current + 1;
}
```

- [ ] **Step 3: Câbler la commande `publish` réelle dans `cli.js`**

Dans `tools/content-cli/cli.js`, modifier le `case 'publish':` existant :
```javascript
    case 'publish':
      if (dry) return validate(entries) && checkPublishable(entries) && publishDryRun(entries);
      if (!(validate(entries) && checkPublishable(entries))) return false;
      const publishable = entries.filter((e) => e.data.status === 'published');
      const { pushDocuments, incrementContentVersion } = await import('./firestore-client.js');
      const byKind = { poi: [], cheats: [] };
      publishable.forEach((e) => byKind[e.kind].push(e.data));
      for (const [kind, docs] of Object.entries(byKind)) {
        if (docs.length) await pushDocuments(kind, docs);
      }
      const newVersion = await incrementContentVersion();
      console.log(`publish: pushed ${publishable.length} document(s), contentVersion → ${newVersion}`);
      return true;
```

Retirer le refus inconditionnel précédent (`if (!dry) { console.error('publish: refusing...'); return false; }`) puisque le vrai push est maintenant implémenté.

- [ ] **Step 4: Vérifier avec un projet réel**

Run (avec `FIREBASE_SERVICE_ACCOUNT_PATH` pointant vers une clé de service valide) : `node cli.js publish`
Expected : les entrées `status: published` de `content/poi/` et `content/cheats/` apparaissent dans Firestore, `contentVersion` incrémenté dans Remote Config. (Aucune entrée actuelle de `content/` n'a `status: published` — les fixtures existantes sont `draft` — donc ce premier run publiera 0 document ; c'est le comportement attendu, valider avec un fixture temporaire marqué `published` si un test de bout en bout est nécessaire avant la vraie mise en production de contenu.)

- [ ] **Step 5: Commit**

```bash
git add tools/content-cli/cli.js tools/content-cli/firestore-client.js tools/content-cli/package.json tools/content-cli/package-lock.json
git commit -m "feat: content-cli publish — real Firestore push + Remote Config version bump"
```

---

### Task 7: Wiring `FirebaseApp.configure()` — activation du projet réel

**Files:**
- Modify: `NeonCompass/App/NeonCompassApp.swift`, `project.yml`
- Create: `NeonCompass/GoogleService-Info.plist` (fourni par l'utilisateur, pas généré)

**⚠️ Cette tâche nécessite le `GoogleService-Info.plist` réel de l'utilisateur — voir prérequis en tête de plan. C'est la seule tâche qui rend la Task 5 réellement fonctionnelle de bout en bout (POI visibles depuis Firestore).**

- [ ] **Step 1: Ajouter le plist au bundle**

Placer le fichier `GoogleService-Info.plist` fourni par l'utilisateur dans `NeonCompass/GoogleService-Info.plist`. Il sera inclus automatiquement via l'entrée `path: NeonCompass` déjà présente dans `project.yml` (aucune folder reference nécessaire, fichier plat comme `Info.plist`).

- [ ] **Step 2: Appeler `FirebaseApp.configure()` au lancement**

Dans `NeonCompass/App/NeonCompassApp.swift` :
```swift
import SwiftUI
import SwiftData
import FirebaseCore

@main
struct NeonCompassApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FoundEntry.self, PersonalPin.self, POICacheEntry.self])
    }
}
```

Noter l'ajout de `POICacheEntry.self` à la liste des modèles SwiftData enregistrés — sans cela, `POIContentStore` (Task 4) ne peut pas persister son cache dans le conteneur réel de l'app (les tests de la Task 4 utilisaient un conteneur en mémoire séparé, cet oubli ne s'y serait pas manifesté).

- [ ] **Step 3: Ajouter `FirebaseCore` aux dépendances de la cible**

Dans `project.yml`, `targets.NeonCompass.dependencies`, ajouter :
```yaml
      - package: Firebase
        product: FirebaseCore
```

- [ ] **Step 4: Build et vérification visuelle de bout en bout**

Run: `Scripts/build.sh`
Expected: `** BUILD SUCCEEDED **`

Publier un POI de test via le CLI (Task 6), puis lancer l'app sur simulateur : l'onglet Carte doit maintenant afficher le POI publié, confirmant le pipeline complet Firestore → sync → cache → `MapModel` → `MapScreen`.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/GoogleService-Info.plist NeonCompass/App/NeonCompassApp.swift project.yml
git commit -m "feat: activate real Firebase project (FirebaseApp.configure, POICacheEntry container)"
```

---

## Self-Review

**Couverture roadmap** : Firebase SPM + protocoles `Core/` (Task 1) ✓, modèles Firestore localisés miroir de `content/schema/` — réutilise directement `POI`/`LocalizedText` du plan 2, qui tolèrent déjà les champs pipeline-only via Codable (Task 2) ✓, cache SwiftData (Task 4) ✓, Remote Config `contentVersion` (Task 3) ✓, CLI admin étendu au push réel (Task 6) ✓.

**Cohérence des types** : `POI` (plan 2) n'est jamais redéfini, seulement décodé depuis une source différente (Firestore au lieu du fixture bundlé) — le contrat `POIRemoteRepository.fetchAll() -> [POI]` garantit qu'aucun code consommateur (`MapModel`, `MapPinsOverlay`, etc.) n'a besoin de changer. `POIContentStore` est le seul nouveau point d'entrée touchant `MapScreen`.

**Séparation du blocage externe** : Tasks 1-5 n'importent et ne testent que du code buildable/testable sans projet Firebase réel (fakes + `FirebaseApp.configure()` jamais appelé avant Task 7). Tasks 6-7 sont explicitement marquées comme nécessitant l'action de l'utilisateur, et peuvent être exécutées en parallèle du reste si le projet Firebase est créé pendant que les Tasks 1-5 s'exécutent.
