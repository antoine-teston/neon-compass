import Foundation

/// Rubrique d'une entrée du fil.
///
/// Décodage TOLÉRANT : une valeur inconnue retombe sur `.announcement` au lieu
/// de lever. C'est ce qui protège le fil d'une panne totale le jour où le
/// pipeline publie une rubrique qu'une version déjà installée ne connaît pas —
/// sans ça, une seule entrée d'un type neuf ferait échouer le décodage du
/// fragment ENTIER, et les clients d'avant verraient un fil vide sans qu'aucune
/// erreur ne le dise. Ajouter une rubrique cesse donc d'être une opération qui
/// exige que tout le parc soit à jour.
enum NewsCategory: String, CaseIterable, Codable, Sendable {
    /// Information officielle sur le jeu ou son édition.
    case announcement
    /// Mise à jour du jeu, après sa sortie.
    case patch
    /// Rendez-vous daté : diffusion, publication de résultats.
    case event
    /// Service pratique : préchargement, stockage, comment s'y prendre.
    case guide
    /// Prix, précommandes, classements, offres commerciales.
    case business
    /// Ce que fait la communauté : créations, mods, exploits de joueurs.
    case community

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NewsCategory(rawValue: raw) ?? .announcement
    }
}

/// Jeu concerné par une entrée.
///
/// Le fil couvre les deux : la presse spécialisée parle autant du jeu en ligne
/// actuel que de celui à venir, et un compagnon qui masquerait tout le premier
/// se priverait des deux tiers de l'actualité. Mais un lecteur doit savoir en un
/// coup d'œil de quoi on lui parle — d'où la pastille sur la carte.
///
/// Ce commentaire affirmait réutiliser le vocabulaire de `MapGame` « plutôt que
/// d'en inventer un second » — tout en déclarant un second type aux mêmes
/// valeurs brutes. Les deux ne sont plus que des alias de `Game`
/// (`Core/Game.swift`), et la tolérance aux valeurs inconnues que ce type
/// portait est descendue dans `init(from:)` ci-dessous, seul endroit qui la veut.
typealias NewsGame = Game

/// Ce que vaut une information, tel que la veille l'a jugé.
///
/// Longtemps resté pipeline-only, ce champ remonte dans le modèle parce qu'il
/// répond à la question que se pose vraiment un lecteur de ce fil : « est-ce
/// sûr ? ». Trois des entrées les plus utiles sont des démentis de rumeurs
/// virales — leur valeur tient entièrement à ce qu'on assume de dire d'où on
/// tient l'information.
///
/// Contrairement à `NewsCategory` et `NewsGame`, pas de repli sur une valeur par
/// défaut : un niveau de confiance inventé serait pire que pas de niveau du tout.
/// L'absence — comme une valeur inconnue — se traduit par `nil` côté `NewsItem`,
/// et la vue n'affiche alors rien. La tolérance est là, mais elle est portée par
/// le site d'appel, pas par un cas fourre-tout dans l'énumération.
enum NewsConfidence: String, CaseIterable, Codable, Sendable {
    case confirmedOfficial = "confirmed-official"
    case multiSource = "multi-source"
    case singleSource = "single-source"
    case rumor
}

/// Les champs restés pipeline-only (`status`, `sources`, `processedFrom`,
/// `sourceClaim`) sont absents ici : Codable ignore silencieusement les clés
/// JSON inconnues au décodage.
///
/// `sources` en particulier n'est PAS embarqué, et pas par oubli : les URL des
/// sources contiennent les marques (`gtaboom.com/rockstar-confirms-…`). Les
/// afficher mettrait à l'écran exactement la surface de marque que la politique
/// stricte évite jusqu'à l'approbation App Store. Elles reviendront avec la
/// bascule (docs/superpowers/plans/2026-07-29-plan-bascule-marques.md).
struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: NewsCategory
    let title: LocalizedText
    let body: LocalizedText
    let publishedAt: String

    /// Absent des entrées publiées avant l'ouverture du fil aux deux jeux :
    /// elles portaient toutes sur celui à venir, d'où le défaut.
    let game: NewsGame

    /// `nil` si le champ est absent OU si sa valeur est inconnue de cette version
    /// de l'app. Dans les deux cas la vue n'affiche pas de niveau — ce qui vaut
    /// mieux qu'un niveau faux, et surtout mieux qu'un fragment entier qui ne se
    /// décode plus parce que le pipeline a ajouté un palier.
    let confidence: NewsConfidence?

    private enum CodingKeys: String, CodingKey {
        case id, category, title, body, publishedAt, game, confidence
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(NewsCategory.self, forKey: .category)
        title = try container.decode(LocalizedText.self, forKey: .title)
        body = try container.decode(LocalizedText.self, forKey: .body)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        // `try?` couvre les deux tolérances que le fil veut, et lui seul : la
        // clé absente d'une entrée écrite avant que le champ n'existe, et une
        // valeur qu'une version future du pipeline produirait sans que l'app
        // installée la connaisse. Un rejet ferait disparaître l'entrée du fil,
        // là où la ranger sous le jeu à venir est le moindre mal.
        game = (try? container.decodeIfPresent(NewsGame.self, forKey: .game)) ?? .leonida
        // `try?` et non `try` : c'est ici qu'un palier de confiance inconnu est
        // absorbé, au lieu de faire tomber le décodage du fragment entier.
        confidence = (try? container.decodeIfPresent(NewsConfidence.self, forKey: .confidence)) ?? nil
    }

    init(
        id: String,
        category: NewsCategory,
        title: LocalizedText,
        body: LocalizedText,
        publishedAt: String,
        game: NewsGame = .leonida,
        confidence: NewsConfidence? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
        self.game = game
        self.confidence = confidence
    }
}
