#if DEBUG
import Foundation

/// Une opération capturée au doigt, en attente de matérialisation en fichier
/// `content/poi/*.json` par `content-cli pull-drafts`.
///
/// Le brouillon naît avec un UUID, jamais avec un identifiant `poi_*` : celui-ci
/// est frappé une seule fois, au Mac, quand le contenu est complet — la frappe
/// demande une clé d'identité qui n'existe pas encore au moment où le doigt se
/// pose. Voir la décision D4 de la spec et `tools/basemap/gtav-poi-ids.mjs`.
struct EditorDraft: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case create, move, delete
    }

    let id: String
    let kind: Kind
    /// Renseignée pour `create` seulement : un déplacement ou une suppression
    /// n'a pas à redire la catégorie du POI visé.
    let category: POICategory?
    /// Destination pour `create` et `move`, absente pour `delete`.
    let position: NormalizedPoint?
    /// Identifiant du POI visé, pour `move` et `delete`.
    let targetPOIID: String?
    /// Facultatif : la capture éclair n'en demande pas. La rédaction — et les
    /// traductions — se font au Mac, où elles sont mieux faites.
    let title: String?
    /// Contribution communautaire adoptée, le cas échéant. Citée dans `sources`
    /// à la matérialisation.
    let sourceContributionID: String?
    let capturedAt: Date

    static func create(
        id: String,
        category: POICategory,
        at position: NormalizedPoint,
        title: String? = nil,
        sourceContributionID: String? = nil,
        capturedAt: Date
    ) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .create,
            category: category,
            position: position,
            targetPOIID: nil,
            title: title,
            sourceContributionID: sourceContributionID,
            capturedAt: capturedAt
        )
    }

    static func move(id: String, poiID: String, to position: NormalizedPoint, capturedAt: Date) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .move,
            category: nil,
            position: position,
            targetPOIID: poiID,
            title: nil,
            sourceContributionID: nil,
            capturedAt: capturedAt
        )
    }

    static func delete(id: String, poiID: String, capturedAt: Date) -> EditorDraft {
        EditorDraft(
            id: id,
            kind: .delete,
            category: nil,
            position: nil,
            targetPOIID: poiID,
            title: nil,
            sourceContributionID: nil,
            capturedAt: capturedAt
        )
    }

    /// Passerelle communauté → éditorial : un spot approuvé devient un brouillon
    /// pré-rempli. C'est ce qui fait que le repérage de la foule finit par
    /// compter dans la progression et les défis, ce qu'un spot communautaire ne
    /// fait pas de lui-même.
    static func adopting(_ spot: Contribution, id: String, capturedAt: Date) -> EditorDraft {
        create(
            id: id,
            category: spot.category,
            at: spot.position,
            title: spot.title,
            sourceContributionID: spot.id,
            capturedAt: capturedAt
        )
    }
}
#endif
