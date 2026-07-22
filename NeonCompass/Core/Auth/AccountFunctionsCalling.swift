import Foundation

protocol AccountFunctionsCalling: Sendable {
    func regenerateHandle() async throws -> String
    func deleteAccount() async throws
}
