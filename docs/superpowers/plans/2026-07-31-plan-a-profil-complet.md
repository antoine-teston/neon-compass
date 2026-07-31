# Plan A — Profil complet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verser les Défis dans le Profil, en sortir les réglages, et libérer l'emplacement d'onglet que prendra le Social.

**Architecture:** Aucune logique métier n'est réécrite. `ProgressionModel` et son chargement sont déplacés tels quels dans un `ProgressionSection` autonome que le Profil embarque. Trois extractions rendent l'opération tenable : le protocole Sign in with Apple sort de la vue vers `Core/Auth/` (il devient testable), les réglages partent dans une feuille `SettingsScreen`, et l'entête d'identité devient une vue à part.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SwiftData, Observation (`@Observable`), Swift Testing, XcodeGen (`project.yml`), Firebase derrière protocoles.

**Spec:** `docs/superpowers/specs/2026-07-31-profil-complet-design.md`

## Global Constraints

- **iOS 26 minimum**, iPhone + iPad (`TARGETED_DEVICE_FAMILY: "1,2"`). Pas de chemin de repli.
- **Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`.** Tout modèle d'écran est `@Observable @MainActor`.
- **SwiftUI seul.** Pas d'UIKit sauf API sans équivalent, et alors confiné à un fichier (`ThemeStore` importe déjà `UIKit` pour l'icône alternative — c'est le précédent).
- **Firebase reste derrière un protocole dans `Core/`.** Aucun `import Firebase*` dans `Features/`.
- **Tests en Swift Testing** (`import Testing`), jamais XCTest.
- **Aucune chaîne littérale visible.** Toute chaîne passe par `NeonCompass/Resources/Localizable.xcstrings`, et `LocalizationCoverageTests` exige les **cinq** locales `en, fr, es, it, de` non vides pour **chaque** clé. Une clé ajoutée sans ses cinq traductions fait échouer la suite.
- **Édition du catalogue à la main, en respectant le format d'Xcode** : indentation 2 espaces, `"clé" : valeur` avec un espace **avant et après** le deux-points. `tools/xcstrings-locale/apply-locale.js` ne convient pas ici : il exige des traductions pour la totalité des clés du catalogue et lève sur toute clé manquante — c'est un outil d'import en masse, pas d'ajout incrémental.
- **XcodeGen glob les sources** (`sources: - path: NeonCompass`) : `project.yml` n'a jamais à être modifié pour un nouveau fichier. MAIS il faut relancer **`xcodegen generate`** après toute création de fichier source, sinon le `.xcodeproj` ne le connaît pas — et `xcodebuild` rapporte alors silencieusement « 0 tests » **au lieu d'un échec de compilation**. C'est le piège qui vide l'étape « vérifier que le test échoue » de tout son sens : on croit voir un échec TDD là où rien n'a été compilé.
- **Jamais de `ToolbarItem` dans un écran d'onglet.** Aucun n'a de `NavigationStack` ; `RootView` les empile dans un `ZStack` sous une barre maison. Un item de toolbar ne s'affiche nulle part et SwiftUI ne signale rien.
- **Interpolation et clés de catalogue.** `Text("clé \(n)")` ne cherche PAS `clé` : SwiftUI construit la clé `clé %lld`, spécificateur compris. La clé du catalogue doit donc le porter (`progress.challenge.foundCount %lld` est le précédent), et le littéral Swift ne le porte jamais. Trois clés du projet ont déjà livré ce défaut, dont deux visibles en production ; `LocalizationCoverageTests.interpolatedCallSitesResolveToACatalogKey` l'attrape désormais. Corollaire : un nombre nu sans phrase autour (`Text("\(n)")`) doit passer par `Text(verbatim:)`, sinon il devient une souche vide dans le catalogue.
- **Les souches `%@` de l'extracteur, à supprimer avant chaque commit.** Compiler un `Text("clé \(n)")` neuf fait ajouter par Xcode une entrée `clé %@` SANS aucune localisation, qui fait échouer `everyKeyHasAllFiveLocales`. Elle est toujours fausse : pour un `Int`, SwiftUI cherche `clé %lld` à l'exécution — Xcode marque d'ailleurs les entrées `%lld` correctes comme `"extractionState" : "stale"`, c'est un désaccord connu entre son extracteur et l'interpolation SwiftUI, et c'est l'extracteur qui a tort. Après le build, vérifier le catalogue et retirer toute entrée dépourvue de bloc `localizations`. Elles reviennent à chaque build : les supprimer une fois ne suffit pas.
- **Marques déposées interdites** dans toute chaîne visible. Les jeux se nomment par leurs chiffres romains nus (`Game.shortLabel` → « V », « VI »).

**Commandes :**

```sh
# Build
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build

# Suite complète
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test

# Une suite précise
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AppleSignInCoordinatorTests
```

## Structure des fichiers

| Fichier | Responsabilité | État |
|---|---|---|
| `NeonCompass/Core/Auth/AppleSignInCoordinator.swift` | Nonce, SHA-256, classification des échecs, extraction du jeton | **Créé** (T1) |
| `NeonCompassTests/Auth/AppleSignInCoordinatorTests.swift` | Sa couverture | **Créé** (T1) |
| `NeonCompass/Features/Settings/SettingsScreen.swift` | La feuille de réglages | **Créé** (T2) |
| `NeonCompass/Features/Settings/SettingsModel.swift` | Choix du chemin de suppression de compte | **Créé** (T2) |
| `NeonCompassTests/Settings/SettingsModelTests.swift` | Sa couverture | **Créé** (T2) |
| `NeonCompass/Features/Profile/ProfileHeaderView.swift` | Entête d'identité + engrenage | **Créé** (T3) |
| `NeonCompass/Features/Profile/ProgressionSection.swift` | Chargement des défis, déplacé de `ProgressionScreen` | **Créé** (T4) |
| `NeonCompass/Features/Profile/ProfileScreen.swift` | Composition de la page | **Modifié** (T2, T3, T4) |
| `NeonCompass/Features/Progression/ProgressionScreen.swift` | — | **Supprimé** (T5) |
| `NeonCompass/App/AppTab.swift` | Les onglets | **Modifié** (T5) |
| `NeonCompass/App/RootView.swift:203-212` | `screen(for:)` | **Modifié** (T5) |
| `NeonCompass/Features/Progression/ProgressionListView.swift` | Cartes de défis + trophées | **Inchangé**, réutilisé |
| `NeonCompass/Features/Progression/ProgressionModel.swift` | Logique de progression | **Inchangé** |

Ordre d'exécution : chaque tâche laisse l'app compilable et fonctionnelle. T4 duplique volontairement la progression (onglet Défis **et** Profil) le temps d'un commit ; T5 retire l'onglet.

---

### Task 1: Extraire le protocole Sign in with Apple

Le nonce et le SHA-256 sont aujourd'hui des `private static` dans une vue (`ProfileScreen.swift:342-353`) : du protocole cryptographique sans un seul test. `ASAuthorizationAppleIDCredential` n'étant pas constructible en test, on introduit un protocole étroit pour ce dont on a besoin.

**Files:**
- Create: `NeonCompass/Core/Auth/AppleSignInCoordinator.swift`
- Create: `NeonCompassTests/Auth/AppleSignInCoordinatorTests.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift:299-353`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `protocol AppleIdentityTokenProviding: Sendable { var identityTokenData: Data? { get } }`
  - `enum AppleSignInFailure: Error, Equatable { case canceled, unexpectedCredentialType, missingIdentityToken, missingNonce, underlying(String) }`
  - `struct AppleSignInCoordinator: Sendable` avec
    `static func makeRawNonce(length: Int = 32) -> String`,
    `static func sha256(_ input: String) -> String`,
    `static func classify(error: any Error) -> AppleSignInFailure`,
    `static func resolve(credential: (any AppleIdentityTokenProviding)?, rawNonce: String?) -> Result<(idToken: String, nonce: String), AppleSignInFailure>`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `NeonCompassTests/Auth/AppleSignInCoordinatorTests.swift` :

```swift
import Testing
import Foundation
@testable import NeonCompass

struct AppleSignInCoordinatorTests {
    private struct FakeCredential: AppleIdentityTokenProviding {
        let identityTokenData: Data?
    }

    @Test func nonceHasRequestedLengthAndAllowedAlphabet() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = AppleSignInCoordinator.makeRawNonce(length: 32)
        #expect(nonce.count == 32)
        #expect(nonce.allSatisfy { allowed.contains($0) })
    }

    @Test func twoNoncesDiffer() {
        #expect(AppleSignInCoordinator.makeRawNonce() != AppleSignInCoordinator.makeRawNonce())
    }

    /// Vecteur connu : c'est ce qui prouve qu'on envoie bien à Apple le hash
    /// attendu, et pas une chaîne d'octets mal formatée.
    @Test func sha256MatchesKnownVector() {
        #expect(
            AppleSignInCoordinator.sha256("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func resolveReturnsTokenAndNonce() throws {
        let credential = FakeCredential(identityTokenData: Data("jeton".utf8))
        let result = AppleSignInCoordinator.resolve(credential: credential, rawNonce: "nonce-1")
        let value = try result.get()
        #expect(value.idToken == "jeton")
        #expect(value.nonce == "nonce-1")
    }

    /// `Result` porte un tuple, donc il n'est pas `Equatable` : on ne peut pas
    /// écrire `#expect(result == .failure(...))`. Le motif ci-dessous est celui
    /// à reprendre pour les trois cas d'échec.
    @Test func resolveRejectsUnexpectedCredentialType() {
        let result = AppleSignInCoordinator.resolve(credential: nil, rawNonce: "nonce-1")
        guard case .failure(let failure) = result else {
            Issue.record("attendu : un échec")
            return
        }
        #expect(failure == .unexpectedCredentialType)
    }

    @Test func resolveRejectsMissingIdentityToken() {
        let credential = FakeCredential(identityTokenData: nil)
        let result = AppleSignInCoordinator.resolve(credential: credential, rawNonce: "nonce-1")
        guard case .failure(let failure) = result else {
            Issue.record("attendu : un échec")
            return
        }
        #expect(failure == .missingIdentityToken)
    }

    /// Le nonce absent signifie que la demande n'a pas été préparée : envoyer
    /// quand même ferait échouer Firebase avec un message opaque.
    @Test func resolveRejectsMissingNonce() {
        let credential = FakeCredential(identityTokenData: Data("jeton".utf8))
        let result = AppleSignInCoordinator.resolve(credential: credential, rawNonce: nil)
        guard case .failure(let failure) = result else {
            Issue.record("attendu : un échec")
            return
        }
        #expect(failure == .missingNonce)
    }

    /// Refermer la feuille n'est pas une panne : c'est le seul échec qui ne
    /// doit produire aucune alerte.
    @Test func canceledIsClassifiedApart() {
        let canceled = NSError(domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1001)
        #expect(AppleSignInCoordinator.classify(error: canceled) == .canceled)
    }

    @Test func otherErrorsKeepTheirMessage() {
        let boom = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boum"])
        #expect(AppleSignInCoordinator.classify(error: boom) == .underlying("boum"))
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AppleSignInCoordinatorTests
```

Attendu : échec de compilation, `cannot find 'AppleSignInCoordinator' in scope`.

- [ ] **Step 3: Écrire l'implémentation**

Créer `NeonCompass/Core/Auth/AppleSignInCoordinator.swift` :

```swift
import Foundation
import CryptoKit
import AuthenticationServices

/// Ce dont le coordinateur a besoin d'un identifiant Apple, et rien de plus.
///
/// `ASAuthorizationAppleIDCredential` n'est pas constructible en test : sans ce
/// protocole, l'extraction du jeton resterait la partie non couverte d'un
/// échange cryptographique. `ASAuthorizationAppleIDCredential` s'y conforme
/// par l'extension ci-dessous, les tests par une structure factice.
protocol AppleIdentityTokenProviding: Sendable {
    var identityTokenData: Data? { get }
}

extension ASAuthorizationAppleIDCredential: AppleIdentityTokenProviding {
    var identityTokenData: Data? { identityToken }
}

/// Pourquoi une connexion Apple a échoué. `canceled` est à part : refermer la
/// feuille est un geste volontaire, pas une panne, et ne doit rien afficher.
enum AppleSignInFailure: Error, Equatable {
    case canceled
    case unexpectedCredentialType
    case missingIdentityToken
    case missingNonce
    case underlying(String)
}

/// Le protocole Sign in with Apple + Firebase, sorti de la vue.
///
/// Un nonce aléatoire part chez Apple **haché** (SHA-256) ; le nonce brut part
/// chez Firebase avec le jeton signé par Apple. Cet aller-retour est ce qui
/// prouve que le jeton a été émis pour CETTE tentative de connexion.
struct AppleSignInCoordinator: Sendable {
    private static let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func makeRawNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func classify(error: any Error) -> AppleSignInFailure {
        if (error as? ASAuthorizationError)?.code == .canceled { return .canceled }
        return .underlying(error.localizedDescription)
    }

    static func resolve(
        credential: (any AppleIdentityTokenProviding)?,
        rawNonce: String?
    ) -> Result<(idToken: String, nonce: String), AppleSignInFailure> {
        guard let credential else { return .failure(.unexpectedCredentialType) }
        guard let data = credential.identityTokenData,
              let idToken = String(data: data, encoding: .utf8) else {
            return .failure(.missingIdentityToken)
        }
        guard let rawNonce else { return .failure(.missingNonce) }
        return .success((idToken: idToken, nonce: rawNonce))
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AppleSignInCoordinatorTests
```

Attendu : 8 tests au vert.

- [ ] **Step 5: Brancher `ProfileScreen` dessus**

Dans `NeonCompass/Features/Profile/ProfileScreen.swift`, supprimer `randomNonceString`, `sha256`, et remplacer le corps de `handleSignInResult` ainsi que l'appel dans `SignInWithAppleButton` :

```swift
            SignInWithAppleButton(.signIn) { request in
                let nonce = AppleSignInCoordinator.makeRawNonce()
                currentNonce = nonce
                request.requestedScopes = []
                request.nonce = AppleSignInCoordinator.sha256(nonce)
            } onCompletion: { result in
                handleSignInResult(result)
            }
```

```swift
    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            let failure = AppleSignInCoordinator.classify(error: error)
            if failure == .canceled { return }
            report(failure)
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
                        report(AppleSignInCoordinator.classify(error: error))
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
        print("ProfileScreen: connexion refusée — \(message)")
        signInError = message
    }
```

Supprimer aussi `import CryptoKit` de `ProfileScreen.swift` — il n'y sert plus.

- [ ] **Step 6: Ajouter les trois clés au catalogue, dans les cinq langues**

Les trois messages étaient des littéraux français en dur (`"Identifiant Apple d'un type inattendu."` etc.) — ils violaient déjà la règle de localisation. Ajouter dans `NeonCompass/Resources/Localizable.xcstrings`, en respectant l'indentation 2 espaces et `"clé" : valeur` :

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `profile.signIn.unexpectedCredential` | Apple returned an unexpected credential type. | L'identifiant Apple reçu est d'un type inattendu. | Apple devolvió un tipo de credencial inesperado. | Apple ha restituito un tipo di credenziale imprevisto. | Apple hat einen unerwarteten Anmeldedatentyp zurückgegeben. |
| `profile.signIn.missingToken` | Apple didn't return an identity token. | Apple n'a pas renvoyé de jeton d'identité. | Apple no devolvió un token de identidad. | Apple non ha restituito un token di identità. | Apple hat kein Identitätstoken zurückgegeben. |
| `profile.signIn.missingNonce` | The request wasn't prepared. Try again. | La demande n'a pas été préparée. Réessaie. | La solicitud no se preparó. Inténtalo de nuevo. | La richiesta non è stata preparata. Riprova. | Die Anfrage wurde nicht vorbereitet. Versuche es erneut. |

Forme d'une entrée, à recopier pour chacune des trois clés :

```json
    "profile.signIn.missingNonce" : {
      "localizations" : {
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Die Anfrage wurde nicht vorbereitet. Versuche es erneut."
          }
        },
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "The request wasn't prepared. Try again."
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La solicitud no se preparó. Inténtalo de nuevo."
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La demande n'a pas été préparée. Réessaie."
          }
        },
        "it" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "La richiesta non è stata preparata. Riprova."
          }
        }
      }
    },
```

Les clés du catalogue sont triées alphabétiquement : insérer chacune à sa place.

- [ ] **Step 7: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert, `LocalizationCoverageTests` compris.

- [ ] **Step 8: Commit**

```bash
git add NeonCompass/Core/Auth/AppleSignInCoordinator.swift \
        NeonCompassTests/Auth/AppleSignInCoordinatorTests.swift \
        NeonCompass/Features/Profile/ProfileScreen.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "refactor(auth): le protocole Sign in with Apple sort de la vue et devient testable

Nonce et SHA-256 étaient des private static dans ProfileScreen : du
protocole cryptographique sans un seul test. Extraits dans
AppleSignInCoordinator, avec un protocole étroit pour l'identifiant Apple,
que ASAuthorizationAppleIDCredential ne permet pas de construire en test.

Les trois messages d'échec étaient des littéraux français en dur — ils
rejoignent le catalogue, dans les cinq langues."
```

---

### Task 2: Sortir les réglages dans une feuille

**Files:**
- Create: `NeonCompass/Features/Settings/SettingsScreen.swift`
- Create: `NeonCompass/Features/Settings/SettingsModel.swift`
- Create: `NeonCompassTests/Settings/SettingsModelTests.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`

**Interfaces:**
- Consumes: `AppleSignInCoordinator` (T1), `ProfileModel`, `ThemeStore`, `FollowedCategoriesStore`, `CommunityModel`, `AuthModel`, `ProEntitlementModel`, `ServerFeaturesModel`.
- Produces:
  - `@Observable @MainActor final class SettingsModel` avec
    `init(profileModel: ProfileModel)`,
    `func deleteAccount(uid: String, serverEnabled: Bool) async -> Bool` (rend `true` en cas de succès),
    `private(set) var deletionFailed: Bool`
  - `struct SettingsScreen: View` avec `init(profileModel: ProfileModel, communityModel: CommunityModel?)`

- [ ] **Step 1: Écrire le test qui échoue**

Créer `NeonCompassTests/Settings/SettingsModelTests.swift` :

```swift
import Testing
@testable import NeonCompass

@MainActor
struct SettingsModelTests {
    private func makeModel(
        functions: FakeAccountFunctions = FakeAccountFunctions(),
        localDeletion: FakeAccountDeleting = FakeAccountDeleting()
    ) -> (SettingsModel, FakeAccountFunctions, FakeAccountDeleting) {
        let profileModel = ProfileModel(
            repository: FakeProfileRepository(),
            functions: functions,
            localDeletion: localDeletion
        )
        return (SettingsModel(profileModel: profileModel), functions, localDeletion)
    }

    /// Serveur actif : la cascade complète (profil, votes, anonymisation des
    /// contributions approuvées) passe par la Cloud Function.
    @Test func serverEnabledUsesCloudCascade() async {
        let (model, functions, localDeletion) = makeModel()
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: true)
        #expect(ok)
        #expect(functions.deleteAccountCallCount == 1)
        #expect(localDeletion.deleteAccountCallCount == 0)
    }

    /// Sans Cloud Functions déployées, l'obligation Apple demeure : le client
    /// efface ce qu'il peut atteindre — progression synchronisée et compte.
    @Test func serverDisabledFallsBackToLocalDeletion() async {
        let (model, functions, localDeletion) = makeModel()
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: false)
        #expect(ok)
        #expect(functions.deleteAccountCallCount == 0)
        #expect(localDeletion.deleteAccountCallCount == 1)
    }

    /// `user.delete()` exige une connexion récente : l'échec le plus probable
    /// se répare en se reconnectant, et il doit donc être DIT.
    @Test func failureIsReported() async {
        let functions = FakeAccountFunctions()
        functions.shouldThrowOnDelete = true
        let (model, _, _) = makeModel(functions: functions)
        let ok = await model.deleteAccount(uid: "uid-1", serverEnabled: true)
        #expect(!ok)
        #expect(model.deletionFailed)
    }
}
```

Ce test exige deux ajouts aux doublures existantes de `NeonCompassTests/Profile/ProfileFakesTests.swift` — un drapeau d'échec sur `FakeAccountFunctions`, et une doublure `FakeAccountDeleting` si elle n'existe pas encore :

```swift
final class FakeAccountDeleting: AccountDeleting {
    nonisolated(unsafe) private(set) var deleteAccountCallCount = 0

    func deleteAccount(uid: String) async throws {
        deleteAccountCallCount += 1
    }
}
```

Et dans `FakeAccountFunctions`, ajouter :

```swift
    nonisolated(unsafe) var shouldThrowOnDelete = false

    struct Boom: Error {}
```

en modifiant `deleteAccount()` :

```swift
    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        if shouldThrowOnDelete { throw Boom() }
    }
```

Vérifier d'abord si `FakeAccountDeleting` existe déjà dans le fichier ; si oui, ne pas la redéclarer.

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/SettingsModelTests
```

Attendu : `cannot find 'SettingsModel' in scope`.

- [ ] **Step 3: Écrire `SettingsModel`**

Créer `NeonCompass/Features/Settings/SettingsModel.swift` :

```swift
import Foundation
import Observation

/// Le seul morceau de logique des réglages : quel chemin de suppression suivre.
///
/// Le reste de l'écran (thème, icône, catégories suivies, blocages) délègue
/// directement à des stores déjà couverts par leurs propres tests. Ce choix-ci
/// n'appartient à aucun d'eux : il dépend de `ServerFeaturesModel`, que la vue
/// lui passe plutôt qu'il ne l'observe — un modèle testable ne va pas chercher
/// Remote Config tout seul.
@Observable
@MainActor
final class SettingsModel {
    private(set) var deletionFailed = false

    private let profileModel: ProfileModel

    init(profileModel: ProfileModel) {
        self.profileModel = profileModel
    }

    func dismissDeletionFailure() {
        deletionFailed = false
    }

    /// Rend `true` si la suppression a abouti. L'appelant enchaîne alors sur la
    /// déconnexion.
    func deleteAccount(uid: String, serverEnabled: Bool) async -> Bool {
        do {
            if serverEnabled {
                try await profileModel.deleteAccount()
            } else {
                try await profileModel.deleteAccountLocally(uid: uid)
            }
            return true
        } catch {
            deletionFailed = true
            return false
        }
    }
}
```

- [ ] **Step 4: Lancer le test pour vérifier qu'il passe**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/SettingsModelTests
```

Attendu : 3 tests au vert.

- [ ] **Step 5: Écrire `SettingsScreen`**

Créer `NeonCompass/Features/Settings/SettingsScreen.swift`. Le contenu est celui de `ProfileScreen` déplacé, **sans changement de comportement** : mêmes conditions Pro, mêmes gardes `serverFeatures.isEnabled`, mêmes alertes.

```swift
import SwiftUI
import SwiftData
import AuthenticationServices
import UIKit

/// Feuille de réglages, ouverte depuis l'entête du Profil.
///
/// En feuille et pas en `toolbar` : aucun écran d'onglet n'a de
/// `NavigationStack` — `RootView` les empile dans un `ZStack` sous une barre
/// maison — donc un `ToolbarItem` ne s'afficherait nulle part, sans erreur ni
/// avertissement. Même motif que `PaywallView`.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @Environment(ThemeStore.self) private var themeStore
    @Environment(ServerFeaturesModel.self) private var serverFeatures
    @Environment(\.modelContext) private var modelContext

    let profileModel: ProfileModel
    let communityModel: CommunityModel?

    @State private var settingsModel: SettingsModel
    @State private var followedCategoriesStore = FollowedCategoriesStore(
        notifier: FirebaseFollowedCategoryNotifier()
    )
    @State private var showDeleteConfirmation = false
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if proEntitlementModel.isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(NCColor.neonCyan)
                        // Les notifications suivies sont envoyées par une Cloud
                        // Function : sans elle, l'écran promettrait un service
                        // qui n'arrive jamais.
                        if serverFeatures.isEnabled {
                            followedCategoriesSection
                        }
                        themeSection
                        iconSection
                    } else {
                        Button("profile.pro.upgradeButton") { showPaywall = true }
                    }

                    if let communityModel {
                        blockedContributorsSection(communityModel)
                    }

                    accountSection
                }
                .padding(24)
            }
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
            // Firebase, et c'est lui qui permet de comprendre le blocage.
            Text(signInError ?? "")
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if authModel.userID == nil {
                Text(serverFeatures.isEnabled ? "profile.signIn.prompt" : "profile.signIn.syncOnlyPrompt")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.85))

                SignInWithAppleButton(.signIn) { request in
                    let nonce = AppleSignInCoordinator.makeRawNonce()
                    currentNonce = nonce
                    request.requestedScopes = []
                    request.nonce = AppleSignInCoordinator.sha256(nonce)
                } onCompletion: { result in
                    handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
            } else {
                if serverFeatures.isEnabled {
                    Button("profile.handle.regenerate") {
                        Task { try? await profileModel.regenerateHandle() }
                    }
                }
                Button("profile.signOut") { try? authModel.signOut() }
                Button("profile.deleteAccount", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
    }

    private func deleteAccount() async {
        guard let userID = authModel.userID else { return }
        if await settingsModel.deleteAccount(uid: userID, serverEnabled: serverFeatures.isEnabled) {
            try? authModel.signOut()
        }
    }
}
```

Déplacer ensuite **sans les modifier** depuis `ProfileScreen.swift` vers ce fichier, en `private` : `themeSection`, `iconSection`, `followedCategoriesSection`, `blockedContributorsSection(_:)`, `neonIconName`, `handleSignInResult(_:)` et `report(_:)` (versions issues de T1).

- [ ] **Step 6: Alléger `ProfileScreen` et ouvrir la feuille**

Dans `ProfileScreen.swift` : supprimer tout ce qui vient d'être déplacé, ajouter `@State private var showSettings = false`, et poser le bouton **dans le contenu**, jamais dans une `toolbar` :

```swift
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("settings.title"))
            }
```

```swift
        .sheet(isPresented: $showSettings) {
            SettingsScreen(profileModel: profileModel, communityModel: communityModel)
        }
```

- [ ] **Step 7: Ajouter les deux clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `settings.title` | Settings | Réglages | Ajustes | Impostazioni | Einstellungen |
| `settings.done` | Done | Terminé | Listo | Fatto | Fertig |

Même forme d'entrée qu'à la tâche 1, insérées à leur place alphabétique.

- [ ] **Step 8: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert.

- [ ] **Step 9: Commit**

```bash
git add NeonCompass/Features/Settings/ NeonCompassTests/Settings/ \
        NeonCompassTests/Profile/ProfileFakesTests.swift \
        NeonCompass/Features/Profile/ProfileScreen.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(settings): les réglages quittent le Profil pour une feuille

La spec fondatrice §5 les voulait derrière une icône ; ils avaient atterri
dans le Profil par défaut, pas par décision. « Supprimer mon compte » cesse
de voisiner l'anneau de progression.

En feuille et pas en toolbar : aucun écran d'onglet n'a de NavigationStack,
un ToolbarItem ne s'y afficherait nulle part — le défaut qui avait masqué le
sélecteur V/VI de la section Codes."
```

---

### Task 3: L'entête d'identité

**Files:**
- Create: `NeonCompass/Features/Profile/ProfileHeaderView.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`

**Interfaces:**
- Consumes: `Profile` (`handle`, `xp`, `level`, `isPremium`), `SettingsScreen` (T2).
- Produces: `struct ProfileHeaderView: View` avec
  `init(profile: Profile?, isSignedIn: Bool, isProEntitled: Bool, pendingContributionCount: Int, onOpenSettings: @escaping () -> Void)`

- [ ] **Step 1: Écrire la vue**

Créer `NeonCompass/Features/Profile/ProfileHeaderView.swift` :

```swift
import SwiftUI

/// Entête du Profil. Utile connecté ou non : hors connexion elle affiche un
/// titre neutre plutôt qu'un mur de connexion, parce que toute la progression
/// en dessous est locale et n'exige aucun compte.
struct ProfileHeaderView: View {
    let profile: Profile?
    let isSignedIn: Bool
    let isProEntitled: Bool
    let pendingContributionCount: Int
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isSignedIn ? (profile?.handle ?? "…") : String(localized: "profile.header.anonymous"))
                        .font(NCTypography.displayTitle)
                        .foregroundStyle(NCColor.neonCyan)
                    if isProEntitled {
                        Label("profile.pro.badge", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(NCColor.neonCyan)
                    }
                }
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("settings.title"))
            }

            if let profile {
                HStack {
                    Text(String(format: String(localized: "profile.level.format"), profile.level))
                        .font(NCTypography.body.bold())
                        .foregroundStyle(NCColor.neonCyan)
                    Spacer()
                    Text(String(format: String(localized: "profile.xp.format"), profile.xp))
                        .font(NCTypography.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                // L'XP ne se gagne que sur les contributions APPROUVÉES : entre
                // l'envoi et la modération, le rang ne bouge pas. Sans cette
                // ligne, le contributeur subit un silence inexplicable.
                if pendingContributionCount > 0 {
                    Text("profile.pending \(pendingContributionCount)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
```

- [ ] **Step 2: Brancher `ProfileScreen` dessus**

Remplacer dans `ProfileScreen.swift` le bloc `HStack` du bouton d'engrenage (T2, étape 6) et l'ancien `levelBadge(_:)` par :

```swift
                ProfileHeaderView(
                    profile: profileModel.profile,
                    // Sans Cloud Functions, `loadProfile` ne trouve aucun document
                    // et le pseudo resterait un « … » perpétuel : c'est la garde que
                    // portait l'ancien `if serverFeatures.isEnabled`.
                    isSignedIn: authModel.userID != nil && serverFeatures.isEnabled,
                    isProEntitled: proEntitlementModel.isProEntitled,
                    pendingContributionCount: communityModel?.myContributions
                        .filter { $0.status == .pending }.count ?? 0,
                    onOpenSettings: { showSettings = true }
                )
```

Supprimer `levelBadge(_:)` de `ProfileScreen.swift`.

- [ ] **Step 3: Ajouter les deux clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `profile.header.anonymous` | Your profile | Ton profil | Tu perfil | Il tuo profilo | Dein Profil |
| `profile.pending %lld` | %lld awaiting review | %lld en attente de relecture | %lld en espera de revisión | %lld in attesa di revisione | %lld warten auf Prüfung |

`profile.pending %lld` porte un `%lld` : `LocalizationCoverageTests.formatSpecifiersMatchAcrossLocales` vérifie que les cinq langues portent le même spécificateur. Aucune ne doit l'omettre.

- [ ] **Step 4: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Profile/ProfileHeaderView.swift \
        NeonCompass/Features/Profile/ProfileScreen.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(profil): une entête d'identité, lisible même sans compte

Hors connexion, l'entête affiche un titre neutre au lieu d'un mur : toute la
progression en dessous est locale et n'exige aucun compte.

Le décompte des contributions en attente y figure. L'XP ne se gagne que sur
les approuvées : sans cette ligne, un contributeur voit son rang immobile
sans savoir pourquoi."
```

---

### Task 4: La progression entre dans le Profil

**Files:**
- Create: `NeonCompass/Features/Profile/ProgressionSection.swift`
- Modify: `NeonCompass/Features/Profile/ProfileScreen.swift`

**Interfaces:**
- Consumes: `ProgressionModel`, `ProgressionListView`, `ContentStore`, `WidgetSummaryCoordinator`, `FirestoreProgressionSync`.
- Produces: `struct ProgressionSection: View` — sans paramètre, elle porte son propre chargement.

À la fin de cette tâche, la progression s'affiche **à deux endroits** : l'onglet Défis, toujours présent, et le Profil. C'est volontaire et ça ne dure qu'un commit — la tâche 5 retire l'onglet.

- [ ] **Step 1: Créer `ProgressionSection` en déplaçant le chargement**

Créer `NeonCompass/Features/Profile/ProgressionSection.swift`. Le corps est celui de `ProgressionScreen.swift` **à l'identique** : `loadModel()`, `reattachSyncIfNeeded()`, `refreshFoundState()` et leurs commentaires sont recopiés sans une modification.

```swift
import SwiftUI
import SwiftData

/// Les défis et les trophées, embarqués dans le Profil.
///
/// Porte son propre chargement plutôt que de le recevoir : c'est exactement
/// celui de l'ancien `ProgressionScreen`, déplacé sans être touché. Deux
/// mécanismes subtils en dépendent — `RootView.hydrateWidgetSummaryFromCache()`
/// construit un second `ProgressionModel` au lancement pour alimenter le
/// widget, et `reattachSyncIfNeeded()` referme une course entre l'entitlement
/// Pro et la construction du modèle. Tous deux sont nés de bugs réels ; les
/// remanier en même temps qu'un déplacement d'écran mêlerait deux risques sans
/// rapport.
struct ProgressionSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSummaryCoordinator.self) private var widgetSummaryCoordinator
    @Environment(AuthModel.self) private var authModel
    @Environment(ProEntitlementModel.self) private var proEntitlementModel
    @State private var model: ProgressionModel?

    var body: some View {
        Group {
            if let model {
                ProgressionListView(model: model)
            } else {
                ProgressView()
            }
        }
        // Cf. FeedScreen : accrochée au ProgressView, cette tâche s'annulait
        // elle-même dès que `model` était assigné. Les QUATRE synchronisations
        // qui suivent ne repartaient donc jamais.
        .task { await loadModel() }
        .onAppear {
            model?.refreshFoundState()
            reattachSyncIfNeeded()
        }
    }

    private func reattachSyncIfNeeded() {
        guard let model, proEntitlementModel.isProEntitled, let userID = authModel.userID else { return }
        let sync = FirestoreProgressionSync()
        guard model.attachSyncIfNeeded(sync) else { return }
        Task {
            let remoteItems = await sync.fetchAll(uid: userID)
            model.reconcile(with: remoteItems)
        }
    }

    private func loadModel() async {
        guard model == nil else { return }
        let poiStore = ContentStore<POI>.live(collectionName: "poi", modelContext: modelContext)
        // Même socle + overlay que la carte : les défis de la carte de
        // référence doivent compter les mêmes POI que ceux qu'on peut y cocher.
        let referenceStore = ContentStore<POI>.live(
            collectionName: "poi_gtav",
            seed: POILoader.bundled,
            modelContext: modelContext
        )
        let collectionStore = ContentStore<POICollection>.live(
            collectionName: "collections",
            seed: POICollectionLoader.bundled,
            modelContext: modelContext
        )
        let trophyStore = ContentStore<Trophy>.live(collectionName: "trophies", modelContext: modelContext)
        let userID = authModel.userID
        let sync: ProgressionSyncing? =
            (proEntitlementModel.isProEntitled && userID != nil) ? FirestoreProgressionSync() : nil
        model = ProgressionModel(
            pois: poiStore.items + referenceStore.items,
            collections: collectionStore.items,
            trophies: trophyStore.items,
            modelContext: modelContext,
            sync: sync,
            widgetSummaryCoordinator: widgetSummaryCoordinator
        )
        try? await poiStore.syncIfNeeded()
        try? await referenceStore.syncIfNeeded()
        try? await collectionStore.syncIfNeeded()
        try? await trophyStore.syncIfNeeded()
        model?.updateCollections(collectionStore.items)
        model?.updatePOIs(poiStore.items + referenceStore.items)
        model?.updateTrophies(trophyStore.items)
        if let sync, let userID {
            let remoteItems = await sync.fetchAll(uid: userID)
            model?.reconcile(with: remoteItems)
        }
    }
}
```

`ProgressionListView` porte aujourd'hui son propre `ScrollView` et son propre fond (`ProgressionListView.swift:7` et `:16`). Elle est désormais **imbriquée** dans le `ScrollView` du Profil : retirer ces deux-là de `ProgressionListView`, et laisser le Profil fournir défilement et fond.

```swift
struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        VStack(spacing: 20) {
            ForEach(model.gamesWithChallenges) { game in
                gameCard(game)
            }
            trophyCard
        }
    }
```

(le `.padding(16)` disparaît aussi — le Profil applique déjà le sien)

- [ ] **Step 2: Composer la page Profil**

Remplacer le corps de `ProfileScreen.body` par :

```swift
    var body: some View {
        ZStack {
            NCColor.nightSky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    ProfileHeaderView(
                        profile: profileModel.profile,
                        // Sans Cloud Functions, `loadProfile` ne trouve aucun document
                        // et le pseudo resterait un « … » perpétuel : c'est la garde que
                        // portait l'ancien `if serverFeatures.isEnabled`.
                        isSignedIn: authModel.userID != nil && serverFeatures.isEnabled,
                        isProEntitled: proEntitlementModel.isProEntitled,
                        pendingContributionCount: communityModel?.myContributions
                            .filter { $0.status == .pending }.count ?? 0,
                        onOpenSettings: { showSettings = true }
                    )

                    ProgressionSection()

                    if authModel.userID != nil, serverFeatures.isEnabled, let communityModel {
                        myContributionsSection(communityModel)
                    }

                    if authModel.userID == nil {
                        signInInvitation
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen(profileModel: profileModel, communityModel: communityModel)
        }
        .task(id: authModel.userID) {
            if let userID = authModel.userID {
                await profileModel.loadProfile(uid: userID)
                if communityModel == nil {
                    communityModel = CommunityModel.live(modelContext: modelContext)
                }
                await communityModel?.loadMyContributions(uid: userID)
            }
        }
    }

    /// Invitation, pas obstacle : elle est en pied de page, sous toute la
    /// progression, et n'empêche rien.
    private var signInInvitation: some View {
        VStack(spacing: 8) {
            Text("profile.signIn.invitation")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("profile.signIn.openSettings") { showSettings = true }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
```

Conserver `myContributionsSection(_:)` et `statusKey(_:)` dans `ProfileScreen.swift`. Supprimer `signedOutContent`, `signedInContent(userID:)` et les états devenus inutiles (`currentNonce`, `signInError`, `showDeleteConfirmation`, `showPaywall`, `deletionFailed`, `followedCategoriesStore`, `themeStore`) — tous sont désormais dans `SettingsScreen`.

- [ ] **Step 3: Ajouter les deux clés au catalogue, dans les cinq langues**

| Clé | en | fr | es | it | de |
|---|---|---|---|---|---|
| `profile.signIn.invitation` | Sign in to contribute spots and sync your progress. | Connecte-toi pour proposer des spots et synchroniser ta progression. | Inicia sesión para proponer lugares y sincronizar tu progreso. | Accedi per proporre luoghi e sincronizzare i tuoi progressi. | Melde dich an, um Orte vorzuschlagen und deinen Fortschritt zu synchronisieren. |
| `profile.signIn.openSettings` | Open settings | Ouvrir les réglages | Abrir ajustes | Apri le impostazioni | Einstellungen öffnen |

- [ ] **Step 4: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert, `ProgressionModelTests` et `ChallengeProgressCalculatorTests` compris — ils n'ont pas été touchés et ne doivent pas bouger.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Features/Profile/ProgressionSection.swift \
        NeonCompass/Features/Profile/ProfileScreen.swift \
        NeonCompass/Features/Progression/ProgressionListView.swift \
        NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(profil): les défis et les trophées entrent dans le Profil

Le chargement est celui de ProgressionScreen, déplacé sans une modification :
deux mécanismes subtils en dépendent (le second ProgressionModel que RootView
construit pour le widget, et la course entre l'entitlement Pro et la
construction du modèle), tous deux nés de bugs réels.

ProgressionListView perd son ScrollView et son fond : elle est désormais
imbriquée dans celui du Profil.

La progression s'affiche temporairement aux deux endroits — l'onglet part au
commit suivant."
```

---

### Task 5: Retirer l'onglet Défis

**Files:**
- Modify: `NeonCompass/App/AppTab.swift:4-26`
- Modify: `NeonCompass/App/RootView.swift:203-212`
- Delete: `NeonCompass/Features/Progression/ProgressionScreen.swift`
- Create: `NeonCompassTests/App/AppTabTests.swift`

**Interfaces:**
- Consumes: `ProgressionSection` (T4).
- Produces: `AppTab` réduit à `feed, cheats, map, profile`.

Aucune migration : `AppModel.selectedTab` est un simple défaut `.feed` non persisté (`App/AppModel.swift:6`). Aucune valeur brute `"progress"` ne traîne dans les préférences d'un utilisateur installé.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `NeonCompassTests/App/AppTabTests.swift` :

```swift
import Testing
@testable import NeonCompass

struct AppTabTests {
    /// L'onglet Défis a fusionné dans le Profil (plan A). Ce test est ce qui
    /// empêche de le réintroduire par accident.
    @Test func progressTabIsGone() {
        #expect(!AppTab.allCases.contains { $0.rawValue == "progress" })
    }
}
```

Le plan A s'arrête à **quatre** onglets : la carte n'est donc plus au centre, et `CompactTabBar` la traite pourtant à part. C'est un état transitoire assumé, que l'onglet Social du plan B referme. Le test qui garde ce centrage appartient au plan B, où il passe — un test volontairement désactivé pendant tout un plan serait un défaut, pas un garde-fou.

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/AppTabTests
```

Attendu : `progressTabIsGone` en échec — l'onglet existe encore.

- [ ] **Step 3: Retirer le cas de `AppTab`**

Dans `NeonCompass/App/AppTab.swift`, supprimer `progress` des trois endroits :

```swift
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case feed, cheats, map, profile

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .feed: "tab.feed"
        case .cheats: "tab.cheats"
        case .map: "tab.map"
        case .profile: "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "newspaper"
        case .cheats: "gamecontroller"
        case .map: "map.fill"
        case .profile: "person.crop.circle"
        }
    }
}
```

Dans `NeonCompass/App/RootView.swift`, retirer la ligne de `screen(for:)` :

```swift
    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .feed: FeedScreen()
        case .map: MapScreen()
        case .cheats: CheatsScreen()
        case .profile: ProfileScreen()
        }
    }
```

Supprimer le fichier :

```bash
git rm NeonCompass/Features/Progression/ProgressionScreen.swift
```

`ProgressionModel.swift`, `ProgressionListView.swift`, `ChallengeProgress.swift`, `Trophy.swift` et `TrophyProgress.swift` **restent** — ils sont utilisés par `ProgressionSection`.

- [ ] **Step 4: Lancer la suite complète**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Attendu : tout au vert. La clé `tab.progress` du catalogue devient inutilisée — la **laisser** : `LocalizationCoverageTests` ne se plaint pas d'une clé orpheline, et le plan B ajoutera `tab.social` à côté.

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/App/AppTab.swift NeonCompass/App/RootView.swift NeonCompassTests/App/AppTabTests.swift
git rm --cached NeonCompass/Features/Progression/ProgressionScreen.swift 2>/dev/null || true
git commit -m "feat(navigation): l'onglet Défis disparaît, son contenu vit dans le Profil

Aucune migration : AppModel.selectedTab est un défaut non persisté, aucune
valeur brute \"progress\" ne traîne chez un utilisateur installé.

La barre passe temporairement à quatre onglets, donc la carte n'est plus
centrée. L'onglet Social du plan B referme cet état."
```

---

### Task 6: Vérification au simulateur

La leçon de la section Codes est explicite : deux défauts d'UI ont compilé, passé les tests et bien lu dans le plan — le mode PlayStation rendait des lettres Xbox, et un `ToolbarItem` ne s'affichait nulle part. Les deux n'ont été vus qu'à l'écran. Cette tâche n'a pas de test automatisé, et c'est assumé.

**Files:** aucun (vérification), sauf correctifs éventuels.

- [ ] **Step 1: Lancer l'app**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl boot "iPhone 17" 2>/dev/null || true
open -a Simulator
```

Installer et lancer la build, puis ouvrir l'onglet Profil.

- [ ] **Step 2: Parcourir la liste de contrôle, hors connexion d'abord**

- [ ] L'entête affiche « Ton profil », pas un bouton de connexion seul
- [ ] L'anneau de progression et les cartes de défis s'affichent
- [ ] Les trophées se cochent et le cochage persiste après redémarrage
- [ ] Le bouton d'engrenage est **visible** et ouvre la feuille
- [ ] L'invitation à se connecter est en pied de page, sous la progression
- [ ] La barre d'onglets compte quatre onglets, aucun ne renvoie sur un écran vide

- [ ] **Step 3: Se connecter, puis reparcourir**

- [ ] Le handle remplace « Ton profil »
- [ ] Niveau et XP s'affichent (ou rien du tout si `ServerFeaturesModel` est faux — pas une ligne vide)
- [ ] « Mes contributions » apparaît
- [ ] Dans la feuille : thème, icône, catégories suivies, contributeurs bloqués, déconnexion, suppression de compte — tous présents et réactifs
- [ ] La suppression de compte demande confirmation avant d'agir

- [ ] **Step 4: Vérifier l'iPad**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

- [ ] La sidebar adaptative montre bien quatre entrées
- [ ] Le Profil ne s'étire pas en une colonne de texte sur toute la largeur
- [ ] La feuille de réglages s'ouvre en feuille, pas en plein écran illisible

- [ ] **Step 5: Commit des correctifs éventuels**

S'il n'y a rien à corriger, ne pas commiter. Sinon, un commit par défaut trouvé, en décrivant **ce qui était visible à l'écran**, pas la ligne changée.

---

## Ce que ce plan ne fait pas

- L'onglet Social (plan B) — l'emplacement est libéré, rien n'y est posé.
- La fusion des deux chemins de construction de `ProgressionModel` : le doublon entre `RootView.hydrateWidgetSummaryFromCache()` et l'écran est connu, documenté dans le code, et laissé tel quel.
- Toute évolution du calcul de progression, de la sync Pro ou du widget.
- Le classement des contributeurs : seul le décompte des contributions en attente est affiché, à partir d'une donnée déjà chargée.
