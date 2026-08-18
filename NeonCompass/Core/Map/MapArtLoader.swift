import UIKit
import ImageIO
import CoreGraphics

/// Charge le SOCLE d'une carte : une image de 4 096 px, dessinée en permanence
/// sous les tuiles.
///
/// Ce fichier portait auparavant deux étages (4 096 et 8 192 px) et un
/// sélecteur à hystérésis. Le pavage les remplace tous les deux à une
/// granularité bien plus fine — `MapTileSet` choisit un niveau parmi trois et
/// n'en charge que la fenêtre visible — et cette simplification était la
/// contrepartie annoncée du chantier, pas un effet de bord.
///
/// **Ce que coûtait l'image unique, mesuré au simulateur** (empreinte, écran
/// Carte, même code et même cadrage) : 127 Mo à 4 096 px, 208 Mo à 6 144,
/// 319 Mo à 8 192 — soit le côté au carré à 60 Mo près, ces 60 Mo étant l'app
/// elle-même. C'est ce mur des 4 octets par pixel qui interdisait d'aller
/// au-delà de 8 192 px sans pavage, et c'est lui que le pavage contourne.
///
/// UNE SEULE image en cache, délibérément : en garder deux doublerait
/// l'empreinte du socle. Le prix est un redécodage à chaque bascule
/// d'habillage, sur une action volontaire.
///
/// **Le décodage ne se fait pas dans `body`.** Il y était synchrone, sur le fil
/// principal, et coûtait 595 à 795 ms pour 8 192 px.
/// `kCGImageSourceShouldCacheImmediately` force la rastérisation DANS la tâche
/// détachée, au lieu de la laisser se déclencher au premier dessin — sans ce
/// drapeau, sortir la lecture du fil principal ne déplacerait que l'ouverture
/// du fichier et le gel resterait entier.
///
/// `@MainActor` parce que le cache est un état mutable partagé. Seul le
/// décodage s'exécute ailleurs.
@MainActor
enum MapArtLoader {
    private struct Key: Hashable {
        let game: MapGame
        let style: MapStyle
    }

    private static var cache: [Key: UIImage] = [:]
    private static var inFlight: [Key: Task<Void, Never>] = [:]

    /// Ce qui est déjà décodé, sans jamais rien décoder ici.
    ///
    /// Se rabat sur l'AUTRE habillage de la même carte plutôt que de rendre
    /// nil : les deux sortent du même cadrage, donc la substitution ne déplace
    /// pas un pixel — elle change les couleurs une fraction de seconde plus
    /// tard. Jamais l'autre CARTE, en revanche : ce serait une autre île.
    static func cached(game: MapGame, style: MapStyle) -> UIImage? {
        for style in [style] + MapStyle.allCases.filter({ $0 != style }) {
            if let image = cache[Key(game: game, style: style)] { return image }
        }
        return nil
    }

    static func isResident(game: MapGame, style: MapStyle) -> Bool {
        cache[Key(game: game, style: style)] != nil
    }

    /// Décode le socle s'il manque, hors du fil principal, puis le range.
    ///
    /// Ne rend rien : l'appelant relit `cached`. Deux appels concurrents pour la
    /// même clé partagent la même tâche.
    static func prepare(game: MapGame, style: MapStyle) async {
        let key = Key(game: game, style: style)
        if cache[key] != nil { return }
        if let running = inFlight[key] {
            await running.value
            return
        }
        let name = game.resourceName(style: style)
        let decode = Task.detached(priority: .userInitiated) { decodedImage(name: name) }
        let store = Task { @MainActor in
            if let image = await decode.value { cache = [key: image] }
            inFlight[key] = nil
        }
        // Posé avant tout point de suspension : un second appel voit la tâche
        // et l'attend au lieu de relancer le décodage.
        inFlight[key] = store
        await store.value
    }

    private nonisolated static func decodedImage(name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MapArt"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }
        return UIImage(cgImage: decoded)
    }
}
