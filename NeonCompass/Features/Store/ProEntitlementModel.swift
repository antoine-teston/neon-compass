import Foundation
import Observation

@Observable
@MainActor
final class ProEntitlementModel {
    private(set) var isProEntitled = false

    private let provider: ProEntitlementProviding
    // nonisolated(unsafe): deinit runs in a nonisolated context even for an
    // @MainActor class (no isolated-deinit in this codebase's Swift mode),
    // so cancelling here must not require the actor hop. Task<Void, Never>
    // is Sendable and .cancel() is safe to call from any thread/isolation,
    // so this is a benign use of nonisolated(unsafe), not a real data race.
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init(provider: ProEntitlementProviding) {
        self.provider = provider
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await isEntitled in provider.entitlementUpdates {
                self.isProEntitled = isEntitled
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isProEntitled = await provider.currentEntitlement()
    }

    func purchase() async {
        isProEntitled = (try? await provider.purchase()) ?? isProEntitled
    }

    func restorePurchases() async {
        isProEntitled = (try? await provider.restorePurchases()) ?? isProEntitled
    }
}
