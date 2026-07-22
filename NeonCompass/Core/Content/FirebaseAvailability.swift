import FirebaseCore

/// Guards against constructing any Firebase-backed type before
/// FirebaseApp.configure() has run (Task 7 of this plan). Firebase's own
/// APIs (Firestore.firestore(), RemoteConfig.remoteConfig()) crash with an
/// uncatchable fatal error if called with no configured app — this is not
/// a throwing Swift error, so it cannot be caught with try?/do-catch.
/// Features never import FirebaseCore directly; they only call this Bool.
enum FirebaseAvailability {
    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }
}
