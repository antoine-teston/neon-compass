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
    /// écrire `#expect(result == .failure(...))`.
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

    /// Deuxième chemin vers le même verdict : des octets qui ne sont pas de
    /// l'UTF-8 valide. Le premier chemin (données absentes) est déjà couvert ;
    /// celui-ci ne l'était pas.
    @Test func resolveRejectsNonUTF8IdentityToken() {
        let credential = FakeCredential(identityTokenData: Data([0xFF, 0xFE]))
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
