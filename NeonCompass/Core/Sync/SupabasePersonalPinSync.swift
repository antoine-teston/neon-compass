import Foundation
import Supabase

/// Implémentation réelle de `PersonalPinSyncing`, adossée à `personal_pins`.
///
/// L'`upsert` porte sur `(uid, id)`, la clé primaire : c'est la base qui garantit
/// l'unicité, pas une chaîne construite à la main. Et l'`id` vient du client,
/// donc une épingle posée hors ligne a déjà son identité définitive quand elle
/// finit par monter.
///
/// Les erreurs sont avalées, comme dans `SupabaseProgressionSync` : le carnet
/// local reste la vérité de l'appareil, la synchronisation est un confort. Le
/// protocole ne lève pas, et ses appelants n'auraient rien à faire d'une erreur
/// qu'ils ne peuvent pas réparer.
final class SupabasePersonalPinSync: PersonalPinSyncing {
    /// Miroir de la ligne. Les clés sont écrites explicitement plutôt que
    /// laissées à une conversion automatique, pour la même raison que dans
    /// `SupabaseProgressionSync` : un décalage de nom ne se verrait qu'à
    /// l'exécution, sur un appareil, en silence.
    private struct Row: Codable {
        let uid: String
        let id: UUID
        let game: String
        let x: Double
        let y: Double
        let title: String
        let note: String
        let icon: String
        let isDone: Bool
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case uid
            case id
            case game
            case x
            case y
            case title
            case note
            case icon
            case isDone = "is_done"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func upload(_ item: PersonalPinSyncItem) async {
        guard let client, let uid = client.auth.currentUser?.id.uuidString else { return }
        let row = Row(
            uid: uid, id: item.id, game: item.game, x: item.x, y: item.y,
            title: item.title, note: item.note, icon: item.icon, isDone: item.isDone,
            createdAt: item.createdAt, updatedAt: item.updatedAt, deletedAt: item.deletedAt
        )
        do {
            try await client.from("personal_pins").upsert(row, onConflict: "uid,id").execute()
        } catch {
            print("SupabasePersonalPinSync: envoi impossible pour \(item.id) — \(error)")
        }
    }

    func fetchAll(uid: String) async -> [PersonalPinSyncItem] {
        guard let client else { return [] }
        do {
            let rows: [Row] = try await client
                .from("personal_pins")
                .select("uid,id,game,x,y,title,note,icon,is_done,created_at,updated_at,deleted_at")
                .eq("uid", value: uid)
                .execute()
                .value
            return rows.map {
                PersonalPinSyncItem(
                    id: $0.id, game: $0.game, x: $0.x, y: $0.y,
                    title: $0.title, note: $0.note, icon: $0.icon, isDone: $0.isDone,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            }
        } catch {
            print("SupabasePersonalPinSync: lecture impossible — \(error)")
            return []
        }
    }
}
