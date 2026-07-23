import Testing
@testable import NeonCompass

final class FakeProEntitlementProvider: ProEntitlementProviding {
    nonisolated(unsafe) var currentEntitlementToReturn = false
    nonisolated(unsafe) var purchaseResultToReturn: Result<Bool, Error> = .success(true)
    nonisolated(unsafe) var restoreResultToReturn: Result<Bool, Error> = .success(true)
    nonisolated(unsafe) private(set) var purchaseCallCount = 0
    nonisolated(unsafe) private(set) var restoreCallCount = 0

    func currentEntitlement() async -> Bool { currentEntitlementToReturn }

    func purchase() async throws -> Bool {
        purchaseCallCount += 1
        return try purchaseResultToReturn.get()
    }

    func restorePurchases() async throws -> Bool {
        restoreCallCount += 1
        return try restoreResultToReturn.get()
    }

    var entitlementUpdates: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
struct ProEntitlementFakesTests {
    @Test func refreshReflectsCurrentEntitlement() async {
        let fake = FakeProEntitlementProvider()
        fake.currentEntitlementToReturn = true
        let model = ProEntitlementModel(provider: fake)

        await model.refresh()

        #expect(model.isProEntitled)
    }

    @Test func purchaseSetsEntitledOnSuccess() async {
        let fake = FakeProEntitlementProvider()
        fake.purchaseResultToReturn = .success(true)
        let model = ProEntitlementModel(provider: fake)

        await model.purchase()

        #expect(model.isProEntitled)
        #expect(fake.purchaseCallCount == 1)
    }

    @Test func purchaseLeavesStateUnchangedOnCancellation() async {
        let fake = FakeProEntitlementProvider()
        fake.purchaseResultToReturn = .success(false)
        let model = ProEntitlementModel(provider: fake)

        await model.purchase()

        #expect(!model.isProEntitled)
    }

    @Test func restorePurchasesReflectsRestoredEntitlement() async {
        let fake = FakeProEntitlementProvider()
        fake.restoreResultToReturn = .success(true)
        let model = ProEntitlementModel(provider: fake)

        await model.restorePurchases()

        #expect(model.isProEntitled)
        #expect(fake.restoreCallCount == 1)
    }
}
