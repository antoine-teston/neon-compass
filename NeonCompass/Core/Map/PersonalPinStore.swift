import Foundation
import Observation
import SwiftData

/// Le carnet de chasse — propriétaire unique des épingles personnelles.
///
/// **Pourquoi il existe.** Les épingles vivaient dans `MapModel`, qui porte déjà
/// le filtrage des POI, l'état trouvé et la synchro de progression : c'est le
/// fichier qui grossit à chaque chantier. Elles sont désormais lues par trois
/// vues — la carte, la fiche, le carnet — dont deux n'ont besoin de rien
/// d'autre. Et le chantier 2 branchera la synchro ici, comme `FoundStore` porte
/// la sienne.
///
/// **Le plafond vit ici, pas dans la vue**, et le droit Pro lui est passé en
/// paramètre : le magasin ne connaît pas `ProEntitlementModel`, ce qui le laisse
/// testable sans StoreKit. `create` renvoie `nil` quand le plafond mord — un
/// `Optional` plutôt qu'un lancer, parce que buter sur le plafond n'est pas une
/// anomalie mais une réponse.
///
/// `@MainActor` : un `ModelContext` de la fenêtre principale, lu par des corps de
/// vues.
@Observable
@MainActor
final class PersonalPinStore {
    /// Toutes cartes confondues, triées par date de création. Le découpage par
    /// carte se fait à la lecture (`pins(for:)`) : la liste entière sert au
    /// décompte du plafond, qui ignore les cartes.
    private(set) var pins: [PersonalPin] = []

    /// Donne au moteur de carte un moyen en O(1) de savoir si le calque a changé.
    /// `PersonalPin` est une classe : comparer les tableaux ne dirait rien d'une
    /// coche basculée, et compter les éléments encore moins.
    private(set) var generation = 0

    /// Vingt en gratuit, TOUTES CARTES CONFONDUES — un plafond par carte en
    /// vaudrait quarante et ne voudrait plus rien dire.
    static let freeCap = 20

    private let modelContext: ModelContext

    /// Nil tant que le droit Pro et le compte ne sont pas tous deux acquis. Le
    /// magasin ne les vérifie pas lui-même — il ne connaît ni
    /// `ProEntitlementModel` ni `AuthModel`, c'est ce qui le laisse testable
    /// sans StoreKit ni réseau. C'est `MapScreen` qui décide de l'attacher.
    private var sync: PersonalPinSyncing?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    /// Relit le disque, **tombes exclues**.
    ///
    /// Relit, comme `FoundStore.refresh` et pour la même raison : tout ne passe
    /// pas par ce magasin. Les tests insèrent directement dans le contexte, et
    /// sans relecture ces écritures « par derrière » resteraient invisibles.
    ///
    /// Le filtre des tombes est ICI, en un seul endroit, et non à chaque site de
    /// lecture : c'est ce qui garantit qu'aucun chemin ne peut oublier de
    /// l'appliquer et faire réapparaître une épingle effacée. `pins` ne contient
    /// donc que des vivantes, et tout ce qui en dérive — `pins(for:)`, le
    /// décompte du plafond — en hérite sans y penser.
    func refresh() {
        let descriptor = FetchDescriptor<PersonalPin>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        pins = (try? modelContext.fetch(descriptor)) ?? []
        generation &+= 1
    }

    func pins(for game: Game) -> [PersonalPin] {
        pins.filter { $0.gameValue == game }
    }

    func isAtCap(isProEntitled: Bool) -> Bool {
        !isProEntitled && pins.count >= Self.freeCap
    }

    /// Pose une épingle sans nom : elle existe d'abord, elle se nomme ensuite
    /// dans sa fiche. C'est ce qui permet d'en poser cinq en dix secondes manette
    /// en main — et ce qui fait qu'un titre vide n'est plus un piège silencieux.
    ///
    /// - Returns: `nil` quand le plafond gratuit est atteint. L'appelant en fait
    ///   un mur, ce n'est pas au magasin de le dessiner.
    @discardableResult
    func create(at point: NormalizedPoint, game: Game, isProEntitled: Bool) -> PersonalPin? {
        guard !isAtCap(isProEntitled: isProEntitled) else { return nil }
        let pin = PersonalPin(x: point.x, y: point.y, game: game, title: "")
        modelContext.insert(pin)
        save()
        refresh()
        upload(pin)
        return pin
    }

    /// Commit d'une SESSION d'édition, jamais d'une frappe.
    ///
    /// La fiche garde le titre et la note dans un `@State` local et n'appelle
    /// ceci qu'à la perte de focus, à la validation ou à la disparition du
    /// panneau. Le piège est mesuré, et son commentaire est encore dans
    /// `MapModel` : taper un caractère dans le champ de nom d'une épingle coûtait
    /// une requête SwiftData PLUS un filtrage des 537 points, parce que chaque
    /// frappe réévaluait le corps de l'écran.
    ///
    /// **N'avance pas la génération**, et c'est délibéré : ni le titre ni la note
    /// ne changent le dessin de l'épingle. Les périmer ferait rebâtir toutes les
    /// pastilles visibles pour un texte que la carte n'affiche pas. Conséquence
    /// acceptée : l'étiquette d'accessibilité de l'épingle porte l'ancien titre
    /// jusqu'au prochain changement de calque.
    func update(_ pin: PersonalPin, title: String, note: String) {
        guard pin.title != title || pin.note != note else { return }
        pin.title = title
        pin.note = note
        pin.updatedAt = .now
        save()
        upload(pin)
    }

    func setIcon(_ icon: PersonalPinIcon, on pin: PersonalPin) {
        guard pin.icon != icon.rawValue else { return }
        pin.icon = icon.rawValue
        pin.updatedAt = .now
        save()
        bumpGeneration()
        upload(pin)
    }

    func toggleDone(_ pin: PersonalPin) {
        pin.isDone.toggle()
        pin.updatedAt = .now
        save()
        bumpGeneration()
        upload(pin)
    }

    /// Suppression LOGIQUE — la ligne reste, datée.
    ///
    /// Un `delete` local ne se propage pas : sans la tombe, une épingle effacée
    /// sur l'iPhone reviendrait depuis l'iPad à la resynchronisation suivante,
    /// puisque l'iPad la possède encore et que rien ne lui dirait qu'elle a été
    /// retirée.
    ///
    /// On ne purge JAMAIS ces lignes, et c'est délibéré : purger rouvre le
    /// danger classique — un appareil resté hors ligne au-delà de la fenêtre n'a
    /// pas vu la tombe et RESSUSCITE l'épingle. Le coût de tout garder est
    /// dérisoire, une ligne d'environ deux cents octets.
    func delete(_ pin: PersonalPin) {
        let now = Date.now
        pin.deletedAt = now
        pin.updatedAt = now
        save()
        refresh()
        upload(pin)
    }

    private func bumpGeneration() {
        generation &+= 1
    }

    private func save() {
        try? modelContext.save()
    }

    // MARK: - Synchronisation (Pro + connecté)

    /// Attache la synchro après coup si elle ne l'était pas déjà.
    ///
    /// Après coup, et pas à la construction : le magasin est bâti dans
    /// `NeonCompassApp`, avant que `ProEntitlementModel.refresh()` n'ait
    /// répondu. Sans ce rattrapage, un abonné verrait son carnet rester local
    /// jusqu'au prochain lancement — c'est exactement la course que
    /// `MapModel.attachSyncIfNeeded` referme pour la progression.
    ///
    /// Renvoie si l'appel a effectivement attaché, pour que l'appelant sache
    /// qu'il lui reste à déclencher la première lecture.
    @discardableResult
    func attachSyncIfNeeded(_ sync: PersonalPinSyncing) -> Bool {
        guard self.sync == nil else { return false }
        self.sync = sync
        return true
    }

    /// Réconciliation dernière-écriture-gagne, ÉPINGLE PAR ÉPINGLE.
    ///
    /// Par épingle et non en bloc : un appareil resté hors ligne longtemps
    /// écraserait sinon tout le carnet de l'autre en se resynchronisant. Même
    /// raisonnement que `FoundStore.reconcile`, et même règle.
    ///
    /// Les tombes distantes s'appliquent comme le reste — c'est tout leur
    /// intérêt — mais une tombe qu'on n'a JAMAIS connue ne crée rien : adopter
    /// la ligne remplirait le disque de fantômes, un par épingle jamais vue.
    func reconcile(with remoteItems: [PersonalPinSyncItem]) {
        // Lit TOUT, tombes comprises, à la différence de `pins` : sans les
        // tombes locales, une épingle qu'on vient d'enterrer serait vue comme
        // inconnue et recréée par la branche d'adoption ci-dessous.
        let all = (try? modelContext.fetch(FetchDescriptor<PersonalPin>())) ?? []
        var byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for item in remoteItems {
            if let local = byID[item.id] {
                guard item.updatedAt > local.updatedAt else { continue }
                local.game = item.game
                local.x = item.x
                local.y = item.y
                local.title = item.title
                local.note = item.note
                local.icon = item.icon
                local.isDone = item.isDone
                local.updatedAt = item.updatedAt
                local.deletedAt = item.deletedAt
            } else {
                guard item.deletedAt == nil else { continue }
                let pin = PersonalPin(
                    id: item.id, x: item.x, y: item.y,
                    game: Game(rawValue: item.game) ?? .reference,
                    title: item.title, note: item.note,
                    icon: PersonalPinIcon.from(rawValue: item.icon),
                    isDone: item.isDone,
                    createdAt: item.createdAt, updatedAt: item.updatedAt
                )
                modelContext.insert(pin)
                byID[item.id] = pin
            }
        }
        save()
        refresh()

        // Ce que le distant ignore n'a jamais été téléversé — une épingle posée
        // hors ligne, ou créée avant que l'abonnement n'existe. Rien d'autre ne
        // la pousserait, faute d'un drapeau « à envoyer » sur le modèle.
        //
        // Parcourt `all`, l'instantané d'AVANT réconciliation : les épingles
        // adoptées à l'instant sont par construction dans `known`, donc les
        // renvoyer serait un aller-retour pour rien. Les tombes locales en font
        // partie — une suppression faite hors ligne doit monter, sinon elle ne
        // se propagerait jamais.
        let known = Set(remoteItems.map(\.id))
        for pin in all where !known.contains(pin.id) { upload(pin) }
    }

    /// Téléverse une épingle, si et seulement si la synchro est attachée.
    ///
    /// Détaché sur une tâche : aucun appelant n'attend le réseau, et le magasin
    /// est `@MainActor`. L'instantané est pris ICI, sur le fil principal, parce
    /// que `PersonalPin` est une classe SwiftData — la passer à la tâche
    /// laisserait lire ses champs depuis un autre fil.
    private func upload(_ pin: PersonalPin) {
        guard let sync else { return }
        let item = PersonalPinSyncItem(
            id: pin.id, game: pin.game, x: pin.x, y: pin.y,
            title: pin.title, note: pin.note, icon: pin.icon, isDone: pin.isDone,
            createdAt: pin.createdAt, updatedAt: pin.updatedAt, deletedAt: pin.deletedAt
        )
        Task { await sync.upload(item) }
    }
}
