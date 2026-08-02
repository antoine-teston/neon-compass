import UIKit

/// `UIApplicationDelegate` est nécessaire pour l'enregistrement APNs :
/// le protocole `App` de SwiftUI n'expose aucun point d'accroche pour
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
/// Volontairement minimal — rien ici ne fait de configuration d'app, ça reste
/// dans `NeonCompassApp`.
///
/// Les méthodes de `UIApplicationDelegate` sont implicitement isolées au
/// main actor (UIKit annote le protocole), donc aucun `@MainActor` explicite
/// n'est nécessaire.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    /// Le jeton n'est plus remis à un SDK tiers mais à notre propre table :
    /// `push_tokens` porte l'abonnement par catégorie, là où FCM offrait des
    /// topics. « Qui suit cette catégorie » redevient une requête SQL.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await APNsFollowedCategoryNotifier.shared.setDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Sans jeton, les abonnements restent en mémoire et repartiront au
        // prochain enregistrement réussi. Rien à réparer ici.
        print("AppDelegate: enregistrement APNs impossible — \(error)")
    }
}
