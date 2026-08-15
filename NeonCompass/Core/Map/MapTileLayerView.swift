import UIKit
import ImageIO

/// Les tuiles, posées à la main dans des `CALayer` ordinaires.
///
/// **Pas de `CATiledLayer`, et c'est le point qui décide de tout ce fichier.**
/// Un `CATiledLayer` hébergé sous SwiftUI déclenche sur iOS 26 une
/// `NSInternalInconsistencyException` — « Modifications to the layout engine
/// must not be performed from a background thread » — levée depuis son fil de
/// dessin `CAImageProviderThread` à travers `_UIHostingView.layoutSubviews()`.
/// Le fil Apple 820296 la documente, un ingénieur Apple a demandé un rapport de
/// bug, et rien n'est corrigé. La même pile en UIKit pur ne reproduit pas :
/// c'est l'hébergement SwiftUI qui déclenche, et c'est exactement notre cas.
///
/// D'où la règle qui gouverne ce fichier : **le décodage sort du fil principal,
/// la mutation de l'arbre de couches jamais.** `decode` est `nonisolated`, tout
/// le reste est `@MainActor`.
///
/// Trois choses que `CATiledLayer` n'aurait pas données : le fondu nous
/// appartient (le « pop-in » était l'objection de la recherche de juillet), le
/// choix de niveau est une fonction pure donc testable (`MapTileSet`), et une
/// tuile d'une seule couleur se peint sans décoder quoi que ce soit.
@MainActor
final class MapTileLayerView: UIView {
    private let contentSize: CGFloat
    private var name: String?
    private var manifest: MapTileManifest?

    /// Le socle, plein cadre, sous toutes les tuiles. Il ne quitte jamais
    /// l'arbre : c'est lui qu'on voit là où une tuile n'est pas encore
    /// décodée, et sous le niveau où l'on n'en charge aucune.
    private let baseLayer = CALayer()

    /// Le fondu des bords, au-dessus des tuiles.
    ///
    /// Les épingles restent nettes sans qu'on ait rien à faire : elles vivent
    /// dans une AUTRE vue du même conteneur, posée au-dessus de celle-ci.
    ///
    /// `zPosition` et non l'ordre d'insertion : `place` ajoute des tuiles après
    /// coup, et une couche ajoutée dans `init` passerait dessous.
    private let fadeLayer = CALayer()

    /// L'échelle d'affichage qui a servi à graver l'image du fondu. La
    /// regraver coûte une boucle sur 232 324 pixels à ×3 (103 684 à ×2), donc
    /// on ne la refait qu'au changement d'appareil — pas à chaque image de
    /// zoom.
    private var fadeImageScale: CGFloat = 0

    /// Les couches actuellement dans l'arbre, par tuile.
    private var placed: [MapTileKey: CALayer] = [:]
    /// Décodages en cours, par tuile — sert à ne pas relancer le même deux
    /// fois pendant un panoramique, où `update` est appelé à chaque image,
    /// et à les annuler dans `clear()`, `setMap` et `deinit` quand ils
    /// deviennent inutiles plutôt que les laisser tourner pour un écran
    /// mort.
    private var decodingTasks: [MapTileKey: Task<Void, Never>] = [:]
    /// Images déjà décodées, gardées au-delà de leur couche.
    ///
    /// C'est ce cache qui remplace l'hystérésis de l'ancien sélecteur d'étage :
    /// repasser un seuil de niveau pendant un pincement ne redécode rien.
    private var cache: [MapTileKey: CGImage] = [:]
    private var cacheOrder: [MapTileKey] = []
    /// 48 tuiles AU-DELÀ de ce qui est à l'écran, pas 48 au total :
    /// `remember` ne compte plus contre ce plafond les clefs encore dans
    /// `placed`, parce que les évincer ne libère rien (leur `CALayer` garde
    /// l'image par une référence forte sur `contents`) et ne fait que
    /// garantir un redécodage complet si un panoramique les ramène. Un jeu
    /// visible en vaut 24 à 140 selon le zoom et l'appareil — largement plus
    /// que 48 dans les cas hauts, ce qu'un simple FIFO sur toutes les clefs
    /// subissait de plein fouet.
    ///
    /// Ces 48 pèsent **~48 Mo** : depuis que `decode` convertit en BGRX, une
    /// tuile occupe 1 Mo et non les 0,25 Mo de sa forme indexée.
    ///
    /// Reste ouvert, et c'est délibéré : un franchissement de niveau vide
    /// `placed` d'un coup (`clear`), ce qui rend tout le jeu quitté
    /// évinçable d'un coup lui aussi — avant comme après ce correctif. La
    /// bonne valeur du plafond attend une mesure réelle sur iPhone et iPad
    /// (tâche 7), pas un arbitrage ici.
    private static let cacheLimit = 48

    private var currentLevel: Int?
    /// Génération de la paire (nom, manifeste), incrémentée à chaque
    /// `setMap` qui change réellement l'un ou l'autre. Capturée par `place`
    /// à son lancement : une génération différente au retour dit que la
    /// carte a changé pendant le décodage — remplace un contrôle sur
    /// `self.name` dont l'ordre, mal placé, laissait passer des doublons à
    /// la bascule d'habillage.
    private var mapGeneration = 0

    init(contentSize: CGFloat) {
        self.contentSize = contentSize
        super.init(frame: CGRect(x: 0, y: 0, width: contentSize, height: contentSize))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.masksToBounds = true
        baseLayer.frame = bounds
        baseLayer.contentsGravity = .resize
        // Le socle est TOUJOURS réduit (4 096 px pour 2 048 pt) : c'est le
        // filtre de minification qui décide de son aspect, et `.trilinear`
        // remplace ici le `.interpolation(.high)` que `mapBody` posait.
        baseLayer.minificationFilter = .trilinear
        baseLayer.magnificationFilter = .linear
        baseLayer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer.addSublayer(baseLayer)
        fadeLayer.frame = bounds
        fadeLayer.zPosition = 1
        // Invisible tant que `updateEdgeFade` n'a rien dit : au repos c'est
        // l'état définitif, et le premier `sync` arrive au tour de boucle
        // suivant.
        fadeLayer.opacity = 0
        // `contentsCenter` n'est honoré qu'avec une gravité redimensionnante ;
        // c'est la valeur par défaut, posée ici pour que la relecture n'ait
        // pas à le savoir.
        fadeLayer.contentsGravity = .resize
        fadeLayer.actions = [
            "contents": NSNull(), "contentsScale": NSNull(),
            "opacity": NSNull(), "position": NSNull(), "bounds": NSNull()
        ]
        layer.addSublayer(fadeLayer)
        // Forme cible/action et non bloc, pour une raison de langage : le jeton
        // rendu par la forme en bloc est un `any NSObjectProtocol`, non
        // `Sendable`, donc inaccessible depuis un `deinit` nonisolated sous
        // concurrence stricte — et il faut bien le retirer quelque part, un
        // observateur en bloc n'étant pas repris automatiquement. Celle-ci l'est
        // depuis iOS 9, et n'a donc rien à ranger.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// Ce que l'on rend sous pression mémoire : les images décodées gardées EN
    /// PLUS de ce qui est à l'écran, et elles seules.
    ///
    /// `placed` n'est pas touché, et ce n'est pas une omission : ces tuiles-là
    /// sont visibles, et leur `CALayer` retient leur image par `contents` de
    /// toute façon — les évincer ne libérerait donc rien, et garantirait
    /// seulement un redécodage complet. Ce qui repart d'ici sera redécodé si un
    /// panoramique y revient : le coût est du travail, jamais un trou à l'écran.
    ///
    /// C'est un filet, pas un réglage : le dimensionnement, lui, reste
    /// `cacheLimit`.
    ///
    /// `@MainActor` par la classe, et c'est licite : UIKit poste cette
    /// notification depuis le fil principal — c'est la même que celle qui
    /// alimente `UIViewController.didReceiveMemoryWarning`.
    @objc private func handleMemoryWarning() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    deinit {
        // Une vue qui disparaît pendant un panoramique ne doit pas laisser
        // ses décodages tourner pour un écran mort.
        decodingTasks.values.forEach { $0.cancel() }
    }

    /// Le socle. Posé par le coordinateur, qui le décode déjà pour l'écran de
    /// repos — cette vue ne va pas le chercher elle-même.
    ///
    /// `addSublayer` empile : le socle étant ajouté dans `init`, toute tuile
    /// posée ensuite lui passe au-dessus sans qu'on ait à gérer d'index. Et
    /// `clear()` ne retire que les tuiles, jamais lui.
    func setBase(_ image: CGImage?) {
        baseLayer.contents = image
        baseLayer.contentsScale = image.map { CGFloat($0.width) / contentSize } ?? 1
    }

    /// Change de carte ou d'habillage. Tout est jeté : les tuiles d'un habillage
    /// ne valent rien pour l'autre, et le socle tient l'écran pendant que les
    /// premières arrivent.
    ///
    /// Garde sur LE NOM ET LE MANIFESTE, pas le nom seul. Si l'appelant
    /// charge le manifeste après coup (`MapTileManifest.load` lit un
    /// fichier : rien n'empêche un premier appel à nil suivi d'un second,
    /// même nom, une fois la lecture terminée), une garde sur le seul nom
    /// laisserait ce second appel ressortir aussitôt : `manifest` resterait
    /// nil pour toujours et aucune tuile ne se poserait jamais — la carte
    /// semblerait normale, juste plus floue au zoom, sans la moindre erreur
    /// pour le signaler.
    func setMap(name: String, manifest: MapTileManifest?) {
        guard name != self.name || manifest != self.manifest else { return }
        self.name = name
        self.manifest = manifest
        currentLevel = nil
        mapGeneration += 1
        clear()
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Pose le fondu pour l'état courant.
    ///
    /// Appelée hors de `update`, et c'est délibéré : `update` rend la main dès
    /// sa première ligne quand la carte n'a pas de manifeste — la carte de
    /// référence, celle sur laquelle l'app ouvre — alors que le fondu la
    /// concerne autant que l'autre.
    func updateEdgeFade(visibleContentRect: CGRect, zoomScale: CGFloat, displayScale: CGFloat) {
        let scale = max(displayScale, 1)
        if fadeImageScale != scale {
            let pixels = MapEdgeFadeImage.bandPixels(displayScale: scale)
            // Le drapeau ne se pose qu'une fois l'image obtenue : sinon un
            // échec de gravure — 930 Ko sous pression mémoire — serait
            // définitif et silencieux, aucun appel ultérieur ne retentant.
            if let image = MapEdgeFadeImage.make(bandPixels: pixels, color: NCColor.nightSkyRGBA) {
                fadeImageScale = scale
                fadeLayer.contents = image
                fadeLayer.contentsCenter = MapEdgeFadeImage.contentsCenter(bandPixels: pixels)
            }
        }
        let fade = MapGeometry.edgeFade(
            band: MapEdgeFadeImage.band,
            contentSize: CGSize(width: contentSize, height: contentSize),
            visibleContentRect: visibleContentRect,
            zoomScale: zoomScale,
            displayScale: scale
        )
        fadeLayer.contentsScale = fade.contentsScale
        fadeLayer.opacity = fade.opacity
    }

    /// Appelée sur CHAQUE image de défilement et de zoom. Tout ce qui est
    /// coûteux doit donc être conditionné : ici, seul le calcul de la fenêtre
    /// est inconditionnel, et il est en O(tuiles visibles).
    func update(visibleContentRect: CGRect, zoomScale: CGFloat, displayScale: CGFloat) {
        guard let manifest, let name else { return }
        let displayable = MapTileSet.displayablePixels(
            zoomScale: zoomScale, contentSize: contentSize, displayScale: displayScale
        )
        guard let level = MapTileSet.level(for: displayable, manifest: manifest) else {
            // Le socle suffit : on rend les couches plutôt que de les garder
            // pour rien, et on annule les décodages en vol — même quand
            // `placed` est encore vide, ce qui arrive si on ressort de la
            // pyramide avant qu'aucun décodage n'ait abouti. Sans le second
            // test, ces décodages continueraient pour un écran qui n'affiche
            // plus que le socle ; ils finiraient bien par être annulés au
            // prochain changement réel de niveau ou de carte, mais c'est un
            // délai, pas une garantie. Les tuiles reviendront du cache si
            // l'on rezoome.
            if !placed.isEmpty || !decodingTasks.isEmpty { clear() }
            currentLevel = nil
            return
        }
        if level != currentLevel {
            currentLevel = level
            clear()
        }
        let wanted = Set(MapTileSet.tiles(
            level: level, visibleContentRect: visibleContentRect,
            contentSize: contentSize, manifest: manifest
        ))
        for (key, layer) in placed where !wanted.contains(key) {
            layer.removeFromSuperlayer()
            placed[key] = nil
        }
        for key in wanted where placed[key] == nil {
            place(key, name: name, manifest: manifest)
        }
    }

    private func clear() {
        placed.values.forEach { $0.removeFromSuperlayer() }
        placed.removeAll()
        // Un décodage en vol pour une tuile qu'on ne veut plus continuerait
        // à tourner pour rien, et sa réponse tardive ferait encore du
        // travail sur le fil principal pour un résultat déjà périmé.
        decodingTasks.values.forEach { $0.cancel() }
        decodingTasks.removeAll()
    }

    private func place(_ key: MapTileKey, name: String, manifest: MapTileManifest) {
        let frame = MapTileSet.frame(for: key, contentSize: contentSize, manifest: manifest)

        // Tuile d'une seule couleur : un aplat, aucun fichier, aucun décodage.
        // 29,3 % des tuiles du niveau le plus fin sont dans ce cas — c'est
        // l'économie la plus rentable du pavage, et elle est exacte.
        if let rgb = manifest.uniformColor(level: key.level, x: key.x, y: key.y) {
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            ).cgColor
            // Même table que les tuiles-image, dans `attach` ci-dessous :
            // inerte aujourd'hui puisque toute mutation précède
            // `addSublayer`, mais un futur ajout qui muterait cette couche
            // après coup ne saurait pas qu'il doit la poser lui-même.
            layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
            self.layer.addSublayer(layer)
            placed[key] = layer
            return
        }

        // Une seule échelle, calculée une fois et employée par les DEUX chemins.
        // 512 px de tuile pour 56,9 pt de cadre au niveau le plus fin : c'est
        // 9. La poser à 1 sur le chemin du cache — et pas sur celui du décodage
        // — ferait rendre la même tuile différemment selon qu'on vient de la
        // découvrir ou d'y revenir, ce qui est exactement la netteté que cette
        // tâche existe pour obtenir.
        let scale = CGFloat(manifest.tile) / frame.width

        if let image = cache[key] {
            placed[key] = attach(image, at: frame, fade: false, scale: scale)
            return
        }

        guard decodingTasks[key] == nil else { return }
        // Capturée maintenant, comparée au retour : dit si `setMap` a changé
        // la carte pendant que ce décodage était en vol.
        let generation = mapGeneration
        let task = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                Self.decode(name: name, key: key)
            }.value
            guard let self else { return }
            // Annulé par `clear()` / `setMap` / `deinit` entre-temps : sortir
            // AVANT de toucher quoi que ce soit, `decodingTasks` compris —
            // pour ne jamais retirer l'entrée d'un décodage plus récent
            // lancé pour la même clef après nous. C'est précisément
            // l'inversion qui produisait des décodages en double à la
            // bascule d'habillage.
            guard !Task.isCancelled else { return }
            self.decodingTasks.removeValue(forKey: key)
            // Génération plutôt que nom : une carte quittée puis retrouvée
            // pendant le décodage ne doit pas repeindre ses tuiles sur la
            // nouvelle.
            guard let image, self.mapGeneration == generation else { return }
            self.remember(key, image)
            // Le zoom ou le panoramique ont pu emporter la tuile pendant le
            // décodage. La poser quand même la laisserait hors écran, et pire,
            // hors de `placed` — donc jamais retirée.
            guard self.currentLevel == key.level, self.placed[key] == nil else { return }
            self.placed[key] = self.attach(image, at: frame, fade: true, scale: scale)
        }
        decodingTasks[key] = task
    }

    /// Le fondu, qui nous appartient précisément parce qu'on pose nous-mêmes.
    /// 0,18 s : assez pour que l'apparition ne clignote pas, assez court pour
    /// qu'un panoramique rapide ne traîne pas un voile derrière lui.
    /// `scale` n'a PAS de valeur par défaut : les deux appelants doivent la
    /// passer, et une omission doit être une erreur de compilation plutôt
    /// qu'une tuile posée à 1.
    private func attach(_ image: CGImage, at frame: CGRect, fade: Bool, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear
        // Les tuiles ne s'animent pas en position : sans cela, chaque pose
        // déclencherait l'animation implicite de `frame` et la tuile
        // arriverait en glissant depuis le coin.
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        self.layer.addSublayer(layer)
        if fade {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.18
            layer.add(animation, forKey: "fade")
        }
        return layer
    }

    private func remember(_ key: MapTileKey, _ image: CGImage) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = image
        while cacheOrder.count > Self.cacheLimit {
            // Ne jamais évincer une tuile encore à l'écran : sa `CALayer`
            // garde l'image en mémoire de toute façon (référence forte sur
            // `contents`), donc l'évincer ne libérerait rien et garantirait
            // seulement un redécodage complet au retour. On cherche depuis
            // la tête (la plus ancienne) la première clef qui n'est PAS
            // dans `placed`.
            guard let index = cacheOrder.firstIndex(where: { placed[$0] == nil }) else {
                // Tout ce qui dépasse le plafond est actuellement posé :
                // rien à évincer sans reprendre à une couche visible. On
                // s'arrête plutôt que de boucler indéfiniment — un jeu
                // visible plus grand que `cacheLimit` est attendu (voir le
                // commentaire de `cacheLimit`), pas une erreur à corriger
                // ici.
                break
            }
            // `remove(at:)` puis suppression de la MÊME clef dans `cache` :
            // les deux collections retirent une entrée chacune, jamais l'une
            // sans l'autre, quel que soit le chemin emprunté par cette
            // boucle.
            cache[cacheOrder.remove(at: index)] = nil
        }
    }

    /// Hors MainActor : les deux étapes coûteuses, décodage ET conversion —
    /// ni l'une ni l'autre n'a besoin d'état partagé.
    ///
    /// Les tuiles livrées sont des PNG en palette 8 bits sans canal alpha :
    /// `CGImageSourceCreateImageAtIndex` seule rend donc un `CGImage`
    /// INDEXÉ de 0,25 Mo, pas un bitmap 32 bits que CoreAnimation puisse
    /// poser tel quel. Sans la conversion ci-dessous, c'est CoreAnimation
    /// qui convertit — À L'AFFICHAGE, sur le fil principal — et c'est elle
    /// la part chère, pas le décodage : mesuré sur 40 tuiles réelles,
    /// 0,96 ms de décodage contre 2,57 ms de conversion. Au franchissement
    /// de niveau (96 tuiles), cela vaut ~247 ms sur Mac et davantage sur
    /// iPhone — assez pour geler le pincement sur le socle flou, puis faire
    /// arriver les tuiles d'un bloc.
    ///
    /// `kCGImageSourceShouldCacheImmediately` force la rastérisation de
    /// l'indexé ICI plutôt qu'au premier dessin ; le redessin qui suit, dans
    /// un contexte au format natif de CoreAnimation (32 bits,
    /// `noneSkipFirst` puisque les tuiles sont opaques — pas de prime à
    /// payer pour un canal alpha inutile), fait le reste du travail qui,
    /// sinon, serait resté sur le fil principal.
    private nonisolated static func decode(name: String, key: MapTileKey) -> CGImage? {
        guard let url = Bundle.main.url(
                forResource: "\(key.x)_\(key.y)", withExtension: "png",
                subdirectory: "MapTiles/\(name)/\(key.level)"
              ),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let indexed = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return nil }

        // Dégradé, pas de trou : une tuile indexée reste affichable, juste
        // plus chère à poser — mieux vaut ça qu'une tuile absente.
        guard let context = CGContext(
            data: nil,
            width: indexed.width,
            height: indexed.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return indexed }
        context.draw(indexed, in: CGRect(x: 0, y: 0, width: indexed.width, height: indexed.height))
        return context.makeImage() ?? indexed
    }
}
