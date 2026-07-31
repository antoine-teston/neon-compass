import Foundation
@preconcurrency import FirebaseFunctions

/// Implémentation réelle de AccountFunctionsCalling, région europe-west1
/// (miroir de functions/src/regenerateHandle.ts / deleteAccount.ts).
final class FirebaseAccountFunctions: AccountFunctionsCalling {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "europe-west1")) {
        self.functions = functions
    }

    func regenerateHandle() async throws -> String {
        let result = try await functions.httpsCallable("regenerateHandle").call()
        guard let data = result.data as? [String: Any], let handle = data["handle"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return handle
    }

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call()
    }
}
