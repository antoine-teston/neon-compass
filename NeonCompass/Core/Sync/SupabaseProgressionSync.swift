import Foundation
import Supabase

/// Implémentation réelle de `ProgressionSyncing`, adossée à la table
/// `progression`.
///
/// Une ligne par item, jamais un blob unique : le dernier-écrivain-gagne se fait
/// **par item**, sinon un appareil resté hors-ligne longtemps écraserait tout
/// l'historique de l'autre en se resynchronisant. La convention d'identifiant
/// `{kind}_{itemID}` de Firestore devient la clé primaire composite
/// `(uid, kind, item_id)`, donc l'`upsert` est la même opération, garantie par
/// la base au lieu de l'être par une chaîne construite à la main.
///
/// Les erreurs sont avalées, comme dans l'implémentation Firestore : la
/// progression locale reste la vérité de l'appareil, la synchronisation est un
/// confort. `ProgressionSyncing` ne lève pas, et ses appelants n'auraient rien
/// à faire d'une erreur qu'ils ne peuvent pas réparer.
final class SupabaseProgressionSync: ProgressionSyncing {
    /// Miroir de la ligne. Les clés sont écrites explicitement plutôt que
    /// laissées à une conversion automatique : `itemID` deviendrait `item_i_d`
    /// avec `.convertToSnakeCase`, et le décalage ne se verrait qu'à
    /// l'exécution, sur un appareil, en silence.
    private struct Row: Codable {
        let uid: String
        let kind: String
        let itemID: String
        let found: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case uid
            case kind
            case itemID = "item_id"
            case found
            case updatedAt = "updated_at"
        }
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func upload(itemID: String, kind: ProgressionItemKind, found: Bool, updatedAt: Date) async {
        guard let client, let uid = client.auth.currentUser?.id.uuidString else { return }
        let row = Row(uid: uid, kind: kind.rawValue, itemID: itemID, found: found, updatedAt: updatedAt)
        do {
            try await client.from("progression").upsert(row, onConflict: "uid,kind,item_id").execute()
        } catch {
            print("SupabaseProgressionSync: envoi impossible pour \(kind.rawValue)/\(itemID) — \(error)")
        }
    }

    func fetchAll(uid: String) async -> [ProgressionSyncItem] {
        guard let client else { return [] }
        do {
            let rows: [Row] = try await client
                .from("progression")
                .select("uid,kind,item_id,found,updated_at")
                .eq("uid", value: uid)
                .execute()
                .value
            return rows.compactMap { row in
                // Une valeur de `kind` inconnue vient forcément d'une version
                // plus récente de l'app : on l'ignore plutôt que de vider tout
                // le résultat — même politique de tolérance qu'ailleurs.
                guard let kind = ProgressionItemKind(rawValue: row.kind) else {
                    print("SupabaseProgressionSync: kind inconnu \(row.kind), ligne ignorée")
                    return nil
                }
                return ProgressionSyncItem(itemID: row.itemID, kind: kind, found: row.found, updatedAt: row.updatedAt)
            }
        } catch {
            print("SupabaseProgressionSync: lecture impossible — \(error)")
            return []
        }
    }
}
