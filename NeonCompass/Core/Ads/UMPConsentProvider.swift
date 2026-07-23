import UIKit
@preconcurrency import UserMessagingPlatform

/// Implémentation réelle de ConsentProviding, adossée à UMP. Ne référence
/// jamais FirebaseApp.configure() ni MobileAds.shared.start() — ce fichier
/// ne fait que résoudre le consentement, l'appelant (RootView) décide quand
/// démarrer le SDK Ads une fois ce signal obtenu.
///
/// API surface verified 2026-07-23 against the actually-resolved UMP SDK
/// headers (v3.1.0, pinned `from: 3.0.0` in project.yml) in
/// `UserMessagingPlatform.xcframework/.../Headers/*.h`, not transcribed from
/// the plan's guessed sketch. Objective-C types carry `NS_SWIFT_NAME`
/// annotations that drop the `UMP` prefix on the Swift side:
/// `UMPConsentInformation` → `ConsentInformation` (with `.shared`, not
/// `.sharedInstance`), `UMPRequestParameters` → `RequestParameters`,
/// `UMPConsentForm` → `ConsentForm`. The `tagForUnderAgeOfConsent` ObjC
/// property is separately renamed via its own `NS_SWIFT_NAME` to
/// `isTaggedForUnderAgeOfConsent`. Both
/// `requestConsentInfoUpdate(with:completionHandler:)` and
/// `loadAndPresentIfRequired(from:completionHandler:)` take an
/// `(NSError?) -> Void` completion handler, which Swift's Clang importer
/// automatically exposes as an `async throws` overload — confirmed against
/// Google's own current Swift sample (`try await
/// ConsentForm.loadAndPresentIfRequired(from: viewController)`), so no
/// manual `withCheckedThrowingContinuation` wrapping is needed here.
///
/// The whole type is `@MainActor`: every UMP header explicitly documents
/// "Must be called on the main thread/queue". `requestConsent()` is called
/// from `OnboardingModel` (itself `@MainActor`), but a `nonisolated async`
/// implementation here would NOT inherit that isolation — Swift would hop
/// it onto the cooperative thread pool, and UMP's `ConsentForm` would then
/// try to build a `WKWebView` off the main thread and crash (reproduced
/// empirically: `Scripts/test.sh` crashed with "Modifying properties of a
/// view's layer off the main thread is not allowed" inside
/// `UMPConsentProvider.requestConsent` before this annotation was added).
/// A non-isolated protocol requirement (`ConsentProviding.requestConsent()`)
/// can be satisfied by a `@MainActor` conforming implementation — the
/// caller's `await` performs the actor hop.
@MainActor
final class UMPConsentProvider: ConsentProviding {
    func requestConsent() async throws -> Bool {
        let parameters = RequestParameters()
        // Tagged for under-age-of-consent is never true for this app — no
        // COPPA-audience content, matches the rest of the app's adult/teen
        // GTA-companion positioning.
        parameters.isTaggedForUnderAgeOfConsent = false

        try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)

        let rootViewController = AdPresentationContext.topViewController()
        try await ConsentForm.loadAndPresentIfRequired(from: rootViewController)

        // canRequestAds is the SDK's own recommended gate (not a manual
        // consentStatus comparison) — true once consent has been gathered
        // aligned with the app's configured messages, or wasn't required.
        return ConsentInformation.shared.canRequestAds
    }
}
