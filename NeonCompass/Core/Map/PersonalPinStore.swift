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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    /// Relit le disque, comme `FoundStore.refresh` et pour la même raison : tout
    /// ne passe pas par ce magasin. Les tests insèrent directement dans le
    /// contexte, et sans relecture ces écritures « par derrière » resteraient
    /// invisibles.
    func refresh() {
        let descriptor = FetchDescriptor<PersonalPin>(sortBy: [SortDescriptor(\.createdAt)])
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
    }

    func setIcon(_ icon: PersonalPinIcon, on pin: PersonalPin) {
        guard pin.icon != icon.rawValue else { return }
        pin.icon = icon.rawValue
        pin.updatedAt = .now
        save()
        bumpGeneration()
    }

    func toggleDone(_ pin: PersonalPin) {
        pin.isDone.toggle()
        pin.updatedAt = .now
        save()
        bumpGeneration()
    }

    /// Suppression PHYSIQUE. Le chantier 2 la bascule en pierre tombale
    /// (`deletedAt`) parce qu'un `delete` local ne se propage pas : sans elle,
    /// une épingle effacée sur l'iPhone reviendrait depuis l'iPad.
    func delete(_ pin: PersonalPin) {
        modelContext.delete(pin)
        save()
        refresh()
    }

    private func bumpGeneration() {
        generation &+= 1
    }

    private func save() {
        try? modelContext.save()
    }
}
