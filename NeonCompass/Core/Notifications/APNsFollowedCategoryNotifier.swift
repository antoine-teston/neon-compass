import Foundation
import Supabase
import UIKit
import UserNotifications

/// Abonnement par catégorie, sans FCM.
///
/// Les topics de FCM étaient une abstraction du fournisseur ; ici l'abonnement
/// est une ligne dans `push_tokens`, et « qui suit cette catégorie » redevient
/// une requête SQL. On y gagne de pouvoir répondre à la question sans quitter la
/// base, et de n'avoir plus qu'un seul jeu de credentials.
///
/// Le jeton d'appareil est déposé par `AppDelegate` au moment où APNs le rend.
/// Il peut donc ne pas être encore là quand l'utilisateur suit sa première
/// catégorie : les catégories sont alors mémorisées et poussées dès que le jeton
/// arrive. Sans ça, suivre une catégorie juste après avoir accordé la permission
/// serait perdu — silencieusement, ce qui est le pire des cas.
actor APNsFollowedCategoryNotifier: FollowedCategoryNotifying {
    static let shared = APNsFollowedCategoryNotifier()

    private struct TokenRow: Encodable {
        let token: String
        let uid: String
        let categories: [String]
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case token
            case uid
            case categories
            case updatedAt = "updated_at"
        }
    }

    private let client: SupabaseClient?
    private var deviceToken: String?
    private var categories: Set<String> = []

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Appelé par `AppDelegate` à la réception du jeton APNs.
    func setDeviceToken(_ token: Data) async {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        await push()
    }

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        if settings.authorizationStatus == .denied { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            // C'est CE geste qui déclenche l'obtention du jeton APNs. Sans lui,
            // `AppDelegate` n'est jamais appelé et aucun abonnement ne part.
            await MainActor.run { UIApplicationShim.registerForRemoteNotifications() }
        }
        return granted
    }

    func subscribe(to category: POICategory) async {
        categories.insert(category.rawValue)
        await push()
    }

    func unsubscribe(from category: POICategory) async {
        categories.remove(category.rawValue)
        await push()
    }

    private func push() async {
        guard let client,
              let deviceToken,
              let uid = client.auth.currentUser?.id.uuidString
        else { return }

        let row = TokenRow(
            token: deviceToken,
            uid: uid,
            categories: categories.sorted(),
            updatedAt: ISO8601DateFormatter().string(from: .now)
        )
        do {
            try await client.from("push_tokens").upsert(row, onConflict: "token").execute()
        } catch {
            print("APNsFollowedCategoryNotifier: abonnement non enregistré — \(error)")
        }
    }
}

/// Isole le seul appel UIKit de ce fichier.
///
/// `registerForRemoteNotifications()` n'a pas d'équivalent SwiftUI : c'est le
/// cas que le CLAUDE.md prévoit — « no UIKit unless a specific API forces it,
/// and then wrapped in one file ».
@MainActor
private enum UIApplicationShim {
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
