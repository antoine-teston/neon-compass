import Foundation
import CryptoKit
import AuthenticationServices
import Security

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
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        // Bruyant délibérément : un échec de la RNG laisserait `randomBytes` à
        // zéro, donc un nonce constant — la protection anti-rejeu disparaîtrait
        // sans que rien ne le dise. Mieux vaut ne pas s'authentifier du tout.
        precondition(status == errSecSuccess, "SecRandomCopyBytes a échoué : \(status)")
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
