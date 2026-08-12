import UIKit
import ImageIO
import CoreGraphics

/// Quelle DÉFINITION de la carte on charge — jamais quelle carte.
///
/// Les images de `MapArt/` sont rendues bien au-delà de l'espace de contenu de
/// 2 048 pt pour limiter le flou au zoom maximal : 4 096 px pour la référence,
/// 8 192 px pour Leonida. Les deux étages sont **deux fichiers**, tous les deux
/// dans le paquet ; `-reduced.png` est produit par
/// `tools/basemap/reduce-mapart.mjs` à partir du natif.
enum MapArtDetail: Sendable, CaseIterable {
    /// Le fichier `-reduced`, quand il existe — sinon le natif, qui est déjà
    /// sous `overviewMaxPixels` (cas des cartes de référence).
    case overview
    /// Le fichier natif.
    case full

    /// Côté de l'étage réduit tel qu'il est LIVRÉ.
    ///
    /// Deux choses en dépendent et doivent rester d'accord : le sélecteur
    /// ci-dessous, qui compare cette valeur aux pixels affichables, et les
    /// fichiers `-reduced.png`. C'est `MapArtResourcesTests` qui l'impose, sur
    /// les octets des fichiers — pas ce commentaire.
    ///
    /// 4 096 px et non ≈2 620, ce que l'écran montre au repos sur un appareil
    /// 3× : la valeur doit couvrir l'iPad, dont l'échelle de repos est ≈0,67 au
    /// lieu de ≈0,43. C'est aussi, pour la carte de référence, exactement le
    /// fichier : à 4 096 px l'étage réduit est l'image entière, et un second
    /// fichier n'apporterait rien.
    static let overviewMaxPixels = 4096

    /// Suffixe du fichier de l'étage réduit — `island-vi-reduced.png`.
    ///
    /// Partagé avec `MapArtResourcesTests`, qui contrôle les fichiers du dépôt :
    /// sans constante commune, renommer le suffixe d'un côté laisserait le test
    /// vert pendant que l'app se rabattrait en silence sur le natif — soit
    /// exactement la panne muette que ce test existe pour couvrir.
    static let reducedSuffix = "-reduced"
}

/// Choisit l'étage à partir du zoom, avec hystérésis.
///
/// Le seuil vient de la géométrie : le contenu fait `contentSize` points,
/// dessinés à `zoomScale × displayScale` pixels par point, donc l'écran ne peut
/// montrer que `contentSize × zoomScale × displayScale` pixels de l'image. Sous
/// `overviewMaxPixels`, les pixels supplémentaires du fichier sont invisibles —
/// **mesuré** : au repos, deux captures prises avec 4 096 et 8 192 px ne se
/// distinguent pas, là où au zoom maximal l'écart se voit sur les libellés.
///
/// `maxUpscale` va plus loin que la géométrie et c'est un JUGEMENT, pas une
/// mesure : entre l'agrandissement 1,0× (indiscernable, mesuré) et 3,75×
/// (visible, mesuré) rien n'a été mesuré, et 1,5× est le milieu prudent. Ce
/// qu'il achète est considérable — sur un appareil 3× il repousse l'étage natif
/// du zoom 0,667 au zoom 1,0, c'est-à-dire hors de toute la plage où l'on
/// consulte la carte, pour un flou qu'on ne voit pas.
///
/// L'hystérésis n'est pas un raffinement. Sans elle, pincer autour du seuil
/// ferait décoder puis libérer 256 Mo à chaque aller-retour, exactement pendant
/// le geste où l'app doit rester fluide.
struct MapArtDetailSelector {
    private(set) var detail: MapArtDetail = .overview

    /// Agrandissement toléré de l'étage réduit avant de payer le natif.
    static let maxUpscale: CGFloat = 1.5
    /// Fraction du seuil de montée sous laquelle on relâche l'étage natif.
    static let releaseFraction: CGFloat = 0.7

    /// Combien de pixels de l'image l'écran peut montrer.
    static func displayablePixels(zoomScale: CGFloat, contentSize: CGFloat, displayScale: CGFloat) -> CGFloat {
        contentSize * max(zoomScale, 0) * max(displayScale, 1)
    }

    /// Rend l'étage retenu APRÈS transition, et non un simple avis : la valeur
    /// dépend de l'étage courant, donc l'appelant ne peut pas la recalculer sans
    /// cet état.
    @discardableResult
    mutating func update(zoomScale: CGFloat, contentSize: CGFloat, displayScale: CGFloat) -> MapArtDetail {
        let displayable = Self.displayablePixels(
            zoomScale: zoomScale, contentSize: contentSize, displayScale: displayScale
        )
        let engage = CGFloat(MapArtDetail.overviewMaxPixels) * Self.maxUpscale
        switch detail {
        case .overview:
            if displayable > engage { detail = .full }
        case .full:
            if displayable < engage * Self.releaseFraction { detail = .overview }
        }
        return detail
    }
}

/// Charge les images de carte plates — pas de streaming par tuiles, une seule
/// image bornée.
///
/// UNE SEULE image en cache, délibérément, et c'est ce qui tient l'empreinte
/// mémoire de l'app : en garder deux doublerait tout ce qui suit. Le prix payé à
/// la place est un redécodage à chaque bascule d'habillage ou d'étage, sur une
/// action volontaire, jamais à l'improviste.
///
/// **Ce que coûte le côté de 8 192 px, mesuré au simulateur, écran Carte, même
/// code et même cadrage :**
///
/// | source   | CoreAnimation | empreinte | pic     |
/// |----------|---------------|-----------|---------|
/// | 4 096 px | 64 Mo         | 127 Mo    | ~440 Mo |
/// | 6 144 px | 144 Mo        | 208 Mo    | 444 Mo  |
/// | 8 192 px | 256 Mo        | 319 Mo    | 806 Mo  |
///
/// L'empreinte est donc **le côté au carré, à 60 Mo près** — ces 60 Mo sont
/// l'app elle-même, identiques dans les trois lignes. Rien d'autre ne persiste :
/// le bitmap source est relâché après téléversement (« CG raster data » retombe
/// à 32 Ko), c'est la surface CoreAnimation qui reste.
///
/// D'où les deux étages. Au repos, l'écran ne montre que ≈2 620 px du carré de
/// 2 048 pt sur un appareil 3× : les 8 192 px du fichier y sont invisibles, et
/// deux captures prises avec 4 096 et 8 192 px ne se distinguent pas. On décode
/// donc réduit par défaut et natif seulement quand la géométrie le justifie
/// (`MapArtDetailSelector`), ce qui ramène le lancement de 319 à 127 Mo sans
/// toucher un seul pixel affiché.
///
/// **Le code livré, mesuré à son tour** (iPhone 17, Leonida, écran Carte ;
/// l'étage forcé par patch temporaire pour que la seule variable soit lui) :
///
/// | régime                        | empreinte | pic      | décodage |
/// |-------------------------------|-----------|----------|----------|
/// | repos, étage réduit (livré)   | 125 Mo    |  431 Mo  | 121 ms   |
/// | repos, natif verrouillé       | 318 Mo    | 1 156 Mo | 331 ms   |
/// | zoom 2,5, sélecteur normal    | 318 Mo    |  811 Mo  | 225+268 ms |
/// | zoom 2,5, réduit verrouillé   | 126 Mo    |  421 Mo  | 109 ms   |
///
/// Les deux lignes de repos retrouvent le tableau du dessus (127 et 319 Mo), les
/// deux lignes de zoom montrent le sélecteur qui fait son travail. Et les deux
/// contre-épreuves visuelles vont dans le sens attendu : au repos l'étage réduit
/// est indiscernable du natif — s'il diffère, c'est en étant légèrement plus net
/// sur les traits fins, le rehaussement étant appliqué à 4 096 px plutôt que
/// laissé à la minification du GPU — tandis qu'au zoom maximal le natif est
/// franchement plus propre sur les libellés (écart maximal 145/255 sur le même
/// cadre). C'est ce dernier point qui justifie de garder les 8 192 px.
///
/// **Deux pièges d'instrument**, tous deux rencontrés ici. `footprint` ne compte
/// PAS un raster produit par `CGImageSourceCreateThumbnailAtIndex` : il annonçait
/// 62 Mo, carte à l'écran, pendant que `ps` en montrait 138 — d'où l'illusion
/// d'une carte non dessinée. Et le RSS de `ps` retient longtemps les pages
/// libérées : sur du code identique il a rendu 305 puis 221 Mo. Les chiffres
/// ci-dessus sont donc des empreintes, sur des décodages ordinaires.
///
/// Ce que l'étage natif reste là pour couvrir : **poser une épingle.** La visée
/// `.place` du moteur cadre à un zoom d'au moins 1,28 sur iPhone
/// (`Coordinator.focus`), donc au-delà du seuil — soumettre un POI se fait sur
/// les pixels natifs, et c'est la contrainte qui a décidé de garder l'asset de
/// 8 192 px plutôt que de le réduire à la source.
///
/// **Le décodage ne se fait plus dans `body`.** Il y était synchrone, sur le fil
/// principal, et coûtait 595 à 795 ms pour un côté de 8 192 px (155 à 242 ms à
/// 4 096) : c'était toute la latence au démarrage.
/// `kCGImageSourceShouldCacheImmediately` force la rastérisation DANS la tâche
/// détachée, au lieu de la laisser se déclencher au premier dessin — sans ce
/// drapeau, sortir la lecture du fil principal ne déplacerait que l'ouverture du
/// fichier et le gel resterait entier.
///
/// **Deux fichiers, et non un sous-échantillonnage à l'exécution.** C'était le
/// premier jet, et la mesure l'a démenti : ImageIO ne décode pas un PNG
/// partiellement, donc `kCGImageSourceThumbnailMaxPixelSize` inflate les
/// 8 192 px puis rééchantillonne (779 à 890 ms sur l'hôte, 1 264 à 1 800 ms au
/// simulateur) là où le décodage entier coûte 69 à 189 ms, et
/// `kCGImageSourceSubsampleFactor` est purement ignoré pour ce format. L'étage
/// « économique » était donc dix fois plus lent que celui qu'il remplaçait, sans
/// même éviter le pic de 256 Mio — l'image entière étant inflatée en chemin.
/// Réduire une fois pour toutes dans `tools/basemap/reduce-mapart.mjs` coûte
/// 4,1 Mo de paquet et rend l'étage réduit réellement moins cher, en temps
/// comme en mémoire.
///
/// `@MainActor` parce que le cache est un état mutable partagé, lu par `body` et
/// par le coordinateur du moteur, tous deux isolés MainActor. Seul le décodage
/// s'exécute ailleurs.
@MainActor
enum MapArtLoader {
    private struct Key: Hashable {
        let game: MapGame
        let style: MapStyle
        let detail: MapArtDetail
    }

    private static var cache: [Key: UIImage] = [:]
    private static var inFlight: [Key: Task<Void, Never>] = [:]

    /// Ce qui est déjà décodé, sans jamais rien décoder ici.
    ///
    /// Se rabat sur une AUTRE version de la même carte plutôt que de rendre nil,
    /// et c'est ce qui rend le décodage asynchrone invisible au lieu d'être un
    /// trou noir : le temps qu'un étage arrive, l'autre reste à l'écran, et le
    /// temps qu'un habillage arrive, l'autre tient sa place — les deux habillages
    /// sortent du même recadrage, donc la substitution ne déplace pas un pixel,
    /// elle change les couleurs une fraction de seconde plus tard.
    ///
    /// Jamais l'autre CARTE, en revanche : ce serait une autre île.
    static func cached(game: MapGame, style: MapStyle, detail: MapArtDetail) -> UIImage? {
        // L'ordre EST la préférence : l'étage exact, puis l'autre étage du même
        // habillage, puis l'autre habillage.
        let details = [detail] + MapArtDetail.allCases.filter { $0 != detail }
        let styles = [style] + MapStyle.allCases.filter { $0 != style }
        for style in styles {
            for detail in details {
                if let image = cache[Key(game: game, style: style, detail: detail)] { return image }
            }
        }
        return nil
    }

    static func isResident(game: MapGame, style: MapStyle, detail: MapArtDetail) -> Bool {
        cache[Key(game: game, style: style, detail: detail)] != nil
    }

    /// Décode l'étage demandé s'il manque, hors du fil principal, puis le range.
    ///
    /// Ne rend rien : l'appelant relit `cached`. Deux appels concurrents pour la
    /// même clé partagent la même tâche — sans ça, traverser le seuil pendant un
    /// pincement lancerait un décodage par image de l'animation.
    static func prepare(game: MapGame, style: MapStyle, detail: MapArtDetail) async {
        let key = Key(game: game, style: style, detail: detail)
        if cache[key] != nil { return }
        if let running = inFlight[key] {
            await running.value
            return
        }
        let name = game.resourceName(style: style)
        let decode = Task.detached(priority: .userInitiated) { decodedImage(name: name, detail: detail) }
        let store = Task { @MainActor in
            if let image = await decode.value {
                // Remplace le cache au lieu d'y ajouter : un seul bitmap
                // résident, tous jeux, habillages et étages confondus. C'est là
                // tout l'intérêt — en garder deux, ce serait payer 320 Mo au
                // lieu de 256.
                cache = [key: image]
            }
            inFlight[key] = nil
        }
        // Posé avant tout point de suspension, donc avant que `store` ne
        // démarre : un second appel voit la tâche et l'attend au lieu de
        // relancer le décodage.
        inFlight[key] = store
        await store.value
    }

    /// Aucune méthode pour relâcher un étage, et ce n'est pas un oubli : ranger
    /// remplace, donc redescendre d'étage libère le natif au moment même où le
    /// réduit arrive — sans jamais laisser l'écran sans image. Une libération
    /// séparée n'aurait que des mauvais moments pour agir.

    /// Hors MainActor : c'est le seul endroit coûteux, et il n'a besoin d'aucun
    /// état partagé — le nom de ressource et l'étage suffisent. L'isoler
    /// ramènerait la rastérisation sur le fil qu'on cherche précisément à
    /// libérer.
    private nonisolated static func decodedImage(name: String, detail: MapArtDetail) -> UIImage? {
        guard let url = imageURL(name: name, detail: detail),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return UIImage(cgImage: decoded)
    }

    /// Le fichier de l'étage demandé.
    ///
    /// Se rabat sur le natif quand `-reduced` n'existe pas, ce qui n'est pas un
    /// filet mais le cas normal des cartes de référence : elles font déjà
    /// 4 096 px, donc leur étage réduit EST le fichier, et en livrer une copie
    /// n'ajouterait que du poids. Le repli couvre au passage le vrai accident —
    /// un `-reduced.png` oublié après régénération donne une carte nette et
    /// coûteuse, jamais une carte noire.
    private nonisolated static func imageURL(name: String, detail: MapArtDetail) -> URL? {
        func url(_ resource: String) -> URL? {
            Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "MapArt")
        }
        if detail == .overview, let reduced = url(name + MapArtDetail.reducedSuffix) { return reduced }
        return url(name)
    }
}
