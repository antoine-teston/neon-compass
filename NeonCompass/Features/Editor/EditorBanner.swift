#if DEBUG
import SwiftUI

/// Bandeau d'état de l'éditeur.
///
/// Porte le marqueur que `Scripts/check-release-binary.sh` cherche dans le
/// binaire Release : si cette chaîne s'y trouve, c'est que l'éditeur a fui hors
/// de `#if DEBUG`. Une garantie qu'on ne vérifie pas n'en est pas une.
struct EditorBanner: View {
    let draftCount: Int
    let undeliveredCount: Int
    let uid: String?
    let pendingMove: Bool

    static let marker = "NCEditorArmedMarker"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // `verbatim` partout ici : cet outillage interne ne sort jamais du
            // binaire de debug et n'a pas à peupler le catalogue des cinq
            // langues, où ses littéraux s'extrayaient en souches vides.
            Text(verbatim: pendingMove
                 ? "Déplacement : appui long sur la nouvelle position"
                 : "Éditeur armé — \(draftCount) brouillon\(draftCount == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))

            // Ce que l'armement CONFISQUE, et pas seulement ce qu'il offre.
            //
            // `MapScreen` rend la main dès que `handleLongPress` ne dit pas
            // `.ignored`, ce qui est le cas de tout appui long sur un éditeur
            // armé : le menu à trois choix ne s'ouvre alors jamais. La règle est
            // voulue — appui long sur le vide = créer — mais rien ne la disait,
            // et elle se lit de l'extérieur comme « proposer un lieu ne marche
            // pas ». Vécu le 2026-08-05 : trois brouillons créés en croyant
            // soumettre, et le « en attente d'envoi » ci-dessous lu comme un
            // envoi bloqué.
            //
            // Court à dessein : le bandeau se dimensionne sur son contenu
            // (`overlay(alignment: .top)`, sans cadre), donc une phrase longue
            // l'étale sur toute la largeur, juste sous la barre de recherche.
            if !pendingMove {
                Text(verbatim: "Appui long = brouillon, pas « Proposer un lieu »")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if undeliveredCount > 0 {
                Text(verbatim: "\(undeliveredCount) en attente d'envoi")
                    .font(.caption2)
                    .foregroundStyle(NCColor.sunsetOrange)
            }

            // Affiché pour être recopié une fois dans firestore.rules — c'est la
            // seule façon simple de connaître son propre UID.
            if let uid {
                Text(uid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityIdentifier(Self.marker)
    }
}
#endif
