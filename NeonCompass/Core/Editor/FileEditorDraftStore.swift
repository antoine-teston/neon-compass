#if DEBUG
import Foundation

/// Écrit les brouillons dans un fichier du dossier Documents de l'app, visible
/// depuis l'app Fichiers.
///
/// Existe parce que le chemin Firestore exige un compte, et qu'un compte exige
/// Sign in with Apple, qui exige l'adhésion payante au programme développeur
/// Apple. Ce repli ne dépend de rien : ni compte, ni réseau, ni règle de
/// sécurité, ni adhésion. On récupère le fichier depuis Fichiers (AirDrop,
/// iCloud Drive, câble) et `content-cli pull-drafts --file` le matérialise
/// exactement comme ceux venus de Firestore.
///
/// Le fichier est un tableau JSON réécrit en entier à chaque capture. À
/// quelques centaines de brouillons c'est sans conséquence, et ça garantit un
/// fichier toujours valide — un ajout en fin de fichier laisserait un JSON
/// tronqué si l'app était tuée au mauvais moment, ce qui est exactement ce qui
/// arrive en session de jeu.
final class FileEditorDraftStore: EditorDraftStore {
    static let fileName = "editor-drafts.json"

    private let url: URL
    private let queue = DispatchQueue(label: "co.antoineteston.neoncompass.editor-drafts")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = base.appending(path: Self.fileName)
    }

    var fileURL: URL { url }

    func save(_ draft: EditorDraft) throws {
        try queue.sync {
            var drafts = Self.load(from: url)
            // Réenregistrer un brouillon de même identifiant le remplace plutôt
            // que de le dupliquer : `pull-drafts` s'y réapparie par la clé
            // d'identité, mais autant ne pas lui donner de doublons à trier.
            drafts.removeAll { $0.id == draft.id }
            drafts.append(draft)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(drafts)
            // Écriture atomique : un remplacement complet interrompu ne doit pas
            // laisser un fichier à moitié écrit.
            try data.write(to: url, options: .atomic)
        }
    }

    /// Rien à attendre : le fichier est déjà sur le disque quand `save` rend la
    /// main. C'est tout l'intérêt de ce repli — il n'y a pas de file d'envoi.
    func waitForDelivery() async throws {}

    static func load(from url: URL) -> [EditorDraft] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EditorDraft].self, from: data)) ?? []
    }
}
#endif
