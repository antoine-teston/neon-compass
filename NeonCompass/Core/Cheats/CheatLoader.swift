import Foundation

/// Socle embarqué des codes, projeté depuis `content/cheats/` par
/// `node cli.js bundle`. Jamais édité à la main.
///
/// Il existe parce que les codes doivent fonctionner au premier lancement et
/// hors ligne : la saisie immédiate ne tient pas si l'écran attend le réseau.
/// Et parce que les codes d'un jeu terminé ne changent plus.
enum CheatLoader {
    enum LoaderError: Error { case missingResource }

    /// Le repli sans sous-dossier n'est pas cosmétique : selon que
    /// `Resources/Cheats` est déclaré `type: folder` ou non dans project.yml,
    /// XcodeGen place le fichier dans `Cheats/` ou à plat à la racine du
    /// bundle. La variante folder est celle attendue, mais un lookup qui
    /// échoue ici vide silencieusement l'écran de tous ses codes.
    static func loadSeed(from bundle: Bundle = .main) throws -> [Cheat] {
        let url = bundle.url(forResource: "seed-cheats", withExtension: "json", subdirectory: "Cheats")
            ?? bundle.url(forResource: "seed-cheats", withExtension: "json")
        guard let url else { throw LoaderError.missingResource }
        return try JSONDecoder().decode([Cheat].self, from: Data(contentsOf: url))
    }

    /// Décodé paresseusement une seule fois pour tout le processus : l'écran
    /// Codes et l'amorçage du widget en ont tous deux besoin.
    static let bundled: [Cheat] = (try? loadSeed()) ?? []
}
