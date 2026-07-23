import Foundation

protocol InterstitialAdProviding: Sendable {
    var isReady: Bool { get }
    func load() async throws
    /// Returns true if the ad was actually presented.
    @MainActor func show() async -> Bool
}
