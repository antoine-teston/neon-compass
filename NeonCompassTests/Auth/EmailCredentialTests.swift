import Foundation
import Testing
@testable import NeonCompass

struct EmailCredentialTests {
    @Test func acceptsAnOrdinaryAddress() {
        #expect(EmailCredential.validate(email: "antoine@example.com", password: "motdepasse") == nil)
    }

    @Test func rejectsAnEmptyAddress() {
        #expect(EmailCredential.validate(email: "   ", password: "motdepasse") == .emptyEmail)
    }

    /// On n'attrape que la faute de frappe évidente. Valider une adresse par
    /// expression régulière est un problème sans solution correcte — la seule
    /// vérification qui vaille est l'envoi d'un message.
    @Test(arguments: [
        "antoine",              // pas d'arobase
        "@example.com",         // pas de partie locale
        "antoine@example",      // pas de point dans le domaine
        "antoine@.com",         // domaine commençant par un point
        "antoine@example.",     // domaine finissant par un point
        "antoine @example.com", // espace
        "a@b@example.com",      // deux arobases
    ])
    func rejectsObviousTypos(_ address: String) {
        #expect(EmailCredential.validate(email: address, password: "motdepasse") == .malformedEmail)
    }

    @Test func rejectsATooShortPassword() {
        let problem = EmailCredential.validate(email: "antoine@example.com", password: "abc")
        #expect(problem == .passwordTooShort(minimum: EmailCredential.minimumPasswordLength))
    }

    /// L'adresse est vérifiée AVANT le mot de passe : dire « mot de passe trop
    /// court » à quelqu'un qui a mal saisi son adresse l'enverrait corriger la
    /// mauvaise chose.
    @Test func reportsTheAddressBeforeThePassword() {
        #expect(EmailCredential.validate(email: "pas-une-adresse", password: "x") == .malformedEmail)
    }

    /// Sans normalisation, « Antoine@Example.com » et « antoine@example.com »
    /// créeraient deux comptes, et la progression semblerait avoir disparu.
    @Test func normalizesCaseAndSurroundingSpace() {
        #expect(EmailCredential.normalized(email: "  Antoine@Example.COM ") == "antoine@example.com")
    }

    /// La longueur minimale est alignée sur le défaut de GoTrue. La durcir ici
    /// sans la durcir côté projet donnerait une règle que rien ne fait
    /// respecter ; l'assouplir donnerait un refus serveur incompréhensible.
    @Test func minimumMatchesTheServerDefault() {
        #expect(EmailCredential.minimumPasswordLength == 6)
    }
}

@MainActor
struct EmailAuthModelTests {
    @Test func signUpOpensASessionWhenConfirmationIsDisabled() async throws {
        let provider = FakeAuthProvider()
        provider.signUpOutcome = .signedIn(uid: "nouveau-compte")
        let model = AuthModel(authProvider: provider)

        try await model.signUp(email: "antoine@example.com", password: "motdepasse")

        #expect(model.userID == "nouveau-compte")
        #expect(model.awaitingEmailConfirmation == false)
    }

    /// L'absence de session n'est PAS un échec : c'est la confirmation d'e-mail
    /// activée sur le projet. La traiter comme une erreur afficherait
    /// « connexion impossible » à quelqu'un dont le compte vient d'être créé.
    @Test func signUpAwaitsConfirmationWithoutClaimingToBeSignedIn() async throws {
        let provider = FakeAuthProvider()
        provider.signUpOutcome = .confirmationRequired
        let model = AuthModel(authProvider: provider)

        try await model.signUp(email: "antoine@example.com", password: "motdepasse")

        #expect(model.userID == nil)
        #expect(model.awaitingEmailConfirmation)
    }

    /// La validation mord AVANT le réseau : rien ne doit partir pour une
    /// adresse qu'on sait déjà mauvaise.
    @Test func invalidCredentialsNeverReachTheProvider() async {
        let provider = FakeAuthProvider()
        let model = AuthModel(authProvider: provider)

        await #expect(throws: EmailCredentialProblem.malformedEmail) {
            try await model.signUp(email: "pas-une-adresse", password: "motdepasse")
        }
        #expect(model.userID == nil)
        #expect(model.awaitingEmailConfirmation == false)
    }

    @Test func signingInWithGoogleSetsTheUserID() async throws {
        let provider = FakeAuthProvider()
        provider.googleUID = "compte-google"
        let model = AuthModel(authProvider: provider)

        try await model.signInWithGoogle()

        #expect(model.userID == "compte-google")
    }

    /// Se connecter après une inscription en attente doit lever l'attente :
    /// sinon le message « relevez vos messages » resterait affiché sous une
    /// session ouverte.
    @Test func aSuccessfulSignInClearsThePendingConfirmation() async throws {
        let provider = FakeAuthProvider()
        provider.signUpOutcome = .confirmationRequired
        let model = AuthModel(authProvider: provider)
        try await model.signUp(email: "antoine@example.com", password: "motdepasse")
        #expect(model.awaitingEmailConfirmation)

        try await model.signIn(email: "antoine@example.com", password: "motdepasse")

        #expect(model.awaitingEmailConfirmation == false)
        #expect(model.userID == "fake-email-uid")
    }

    /// Le schéma de retour OAuth vit des DEUX côtés d'une frontière que le
    /// compilateur ne voit pas : l'Info.plist et la liste d'URL autorisées du
    /// projet. Une dérive silencieuse laisserait le navigateur ouvert sur une
    /// page blanche.
    @Test func theOAuthRedirectMatchesTheDeclaredURLScheme() throws {
        let url = SupabaseAuthProvider.oauthRedirectURL
        #expect(url.scheme == "co.antoineteston.neoncompass")

        let plist = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let declared = plist.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(declared.contains(url.scheme ?? ""))
    }
}
