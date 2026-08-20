import SwiftData
import Testing
@testable import NeonCompass

/// Le moteur de carte ne repousse son contenu que si le jeton a changé. Un
/// changement qui n'atteindrait pas le jeton ne serait pas une lenteur : ce
/// serait une carte qui MENT — un point ajouté qui n'apparaît pas, une épingle
/// supprimée qui reste. Ces tests portent donc sur les compteurs qui alimentent
/// ce jeton, pas sur le jeton lui-même (dont l'égalité est synthétisée).
@MainActor
struct MapContentTokenTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func samplePOIs() -> [POI] {
        [
            POI(id: "a", category: .landmark, position: NormalizedPoint(x: 0.1, y: 0.1),
                title: LocalizedText(en: "Alpha", fr: nil, es: nil, it: nil, de: nil), note: nil),
            POI(id: "b", category: .collectible, position: NormalizedPoint(x: 0.2, y: 0.2),
                title: LocalizedText(en: "Beta", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ]
    }

    // MARK: - Épingles personnelles

    /// Le cas qui a motivé ce compteur : sans lui, poser une épingle ne
    /// changerait rien de comparable et la carte ne la dessinerait jamais.
    @Test func addingAPersonalPinAdvancesItsGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let before = store.generation
        store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)
        #expect(store.generation != before)
        #expect(store.pins.count == 1)
    }

    /// Supprimer compte autant qu'ajouter : une épingle retirée doit disparaître.
    @Test func deletingAPersonalPinAdvancesItsGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        let before = store.generation
        store.delete(pin)
        #expect(store.generation != before)
        #expect(store.pins.isEmpty)
    }

    /// Deux épingles successives doivent donner deux générations distinctes —
    /// un compteur qui se contenterait de basculer entre deux valeurs
    /// retomberait sur la précédente une fois sur deux.
    @Test func successivePersonalPinsNeverRepeatAGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        var seen: Set<Int> = [store.generation]
        for index in 0..<5 {
            store.create(at: NormalizedPoint(x: 0.1 * Double(index), y: 0.5), game: .reference, isProEntitled: true)
            #expect(seen.insert(store.generation).inserted, "génération déjà vue au tour \(index)")
        }
    }

    // MARK: - Points d'intérêt

    /// L'état « trouvé » se rend DANS la pastille (une coche remplace le
    /// glyphe). Il doit donc atteindre le jeton, sans quoi cocher un lieu
    /// depuis sa fiche ne changerait rien à l'écran — mais il l'atteint
    /// désormais par `foundPOIIDs`, que le jeton compare directement.
    @Test func togglingFoundChangesTheFoundSet() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.foundPOIIDs
        model.toggleFound(samplePOIs()[0])
        #expect(model.foundPOIIDs != before)
    }

    /// Le pendant, et c'est la vraie raison de ce changement : cocher un lieu ne
    /// doit PAS faire avancer la génération des POI.
    ///
    /// Cette génération est la clé d'invalidation de `MapClusterCache` : la faire
    /// avancer réagrège les cinq cent trente-sept points et rebâtit toutes les
    /// pastilles, alors que la liste dessinée est exactement la même — un lieu
    /// coché reste un lieu affiché. C'était la lenteur du marquage.
    @Test func togglingFoundDoesNotAdvanceThePOIGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.toggleFound(samplePOIs()[0])
        #expect(model.poisGeneration == before)
    }

    /// Sauf sous « masquer les trouvés » : là, cocher RETIRE le point de la liste
    /// dessinée, donc la composition change et la génération doit bouger. C'est
    /// la seule exception, et l'oublier ferait rester à l'écran un point que le
    /// mode est censé faire disparaître.
    @Test func togglingFoundAdvancesTheGenerationWhenFoundAreHidden() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        model.hideFoundPOIs = true
        let before = model.poisGeneration
        model.toggleFound(samplePOIs()[0])
        #expect(model.poisGeneration != before)
        #expect(model.filteredPOIs.count == 1)
    }

    /// Filtrer change la liste dessinée.
    @Test func filteringAdvancesThePOIGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.activeCategories = [.landmark]
        #expect(model.poisGeneration != before)
    }

    /// Et l'arrivée du contenu distant aussi — c'est le chemin par lequel les
    /// vrais points remplacent le socle embarqué.
    @Test func updatingPOIsAdvancesTheGeneration() {
        let model = MapModel(pois: samplePOIs(), modelContext: makeContext())
        let before = model.poisGeneration
        model.updatePOIs(samplePOIs() + [
            POI(id: "c", category: .vehicle, position: NormalizedPoint(x: 0.9, y: 0.9),
                title: LocalizedText(en: "Gamma", fr: nil, es: nil, it: nil, de: nil), note: nil),
        ])
        #expect(model.poisGeneration != before)
        #expect(model.filteredPOIs.count == 3)
    }

    // MARK: - Ce que le jeton doit distinguer

    /// La sélection d'une fiche, elle, ne doit RIEN changer au contenu de la
    /// carte : c'est exactement ce que le court-circuit exploite. Si un jour
    /// une fiche ouverte modifiait le rendu d'une pastille, il faudrait
    /// l'ajouter au jeton — ce test le rappellerait.
    @Test func selectingAPOIChangesNoGeneration() {
        let context = makeContext()
        let model = MapModel(pois: samplePOIs(), modelContext: context)
        let store = PersonalPinStore(modelContext: context)
        let pois = model.poisGeneration
        let pins = store.generation
        model.selection = .poi(model.filteredPOIs[0])
        model.selection = nil
        #expect(model.poisGeneration == pois)
        #expect(store.generation == pins)
    }

    /// Et sélectionner une ÉPINGLE non plus : ouvrir sa fiche ne redessine pas le
    /// calque. Le cas est distinct du précédent depuis que le panneau accueille
    /// deux natures — c'est la seule des deux qui puisse être mutée par la fiche
    /// ouverte, donc celle où la confusion coûterait.
    @Test func selectingAPersonalPinChangesNoGeneration() {
        let context = makeContext()
        let model = MapModel(pois: samplePOIs(), modelContext: context)
        let store = PersonalPinStore(modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        let pois = model.poisGeneration
        let pins = store.generation
        model.selection = .pin(pin)
        model.selection = nil
        #expect(model.poisGeneration == pois)
        #expect(store.generation == pins)
    }

    // MARK: - L'épingle en cours de pose

    /// Exception assumée à la règle de cette suite — « on teste les compteurs,
    /// pas l'égalité synthétisée ».
    ///
    /// L'épingle de placement n'a pas de compteur : elle EST dans le jeton, en
    /// valeur. Ce qu'on garde ici n'est donc pas l'égalité de Swift mais le fait
    /// que le champ y figure. L'oublier ne produirait aucune erreur de
    /// compilation et une épingle clouée à son point de départ — le tap la
    /// déplacerait dans l'état, sans que rien ne soit repoussé vers la vue
    /// hébergée. Construire le jeton à la main fait de ce test la sentinelle
    /// qu'on veut : ajouter un champ le casse, donc oblige à se demander s'il
    /// doit invalider.
    @Test func movingThePlacementPinChangesTheToken() {
        func token(
            at x: Double,
            category: POICategory = .landmark,
            unpublished: Int = 0
        ) -> TiledMapRepresentable.ContentToken {
            TiledMapRepresentable.ContentToken(
                game: .leonida,
                style: .neon,
                poisGeneration: 0,
                spotsGeneration: 0,
                myUnpublishedGeneration: unpublished,
                personalPinsGeneration: 0,
                showPersonalPins: true,
                draftPins: [],
                placement: MapPlacementPin(position: NormalizedPoint(x: x, y: 0.5), category: category),
                routeTarget: nil,
                foundPOIIDs: [],
                canAdopt: false
            )
        }

        #expect(token(at: 0.4) != token(at: 0.7), "déplacer l'épingle doit repousser le contenu")
        #expect(
            token(at: 0.4) != token(at: 0.4, category: .safehouse),
            "changer de catégorie change la couleur de l'épingle, donc son dessin"
        )
        // Une proposition envoyée n'atteint le moteur que par là : sur une carte
        // encore vide, rien d'autre ne bouge jamais.
        #expect(
            token(at: 0.4) != token(at: 0.4, unpublished: 1),
            "une proposition de plus en attente doit repousser le contenu"
        )
        #expect(token(at: 0.4) == token(at: 0.4), "rien n'a bougé : ne pas tout reconstruire")
    }

    // MARK: - La cible du parcours

    /// Même sentinelle que ci-dessus, pour l'autre valeur portée par le jeton.
    ///
    /// Ce test répond à la question que la précédente a posée en cassant : la
    /// cible du parcours DOIT invalider. Sans elle dans le jeton, avancer d'une
    /// étape ne repousserait rien — la pastille resterait clouée sur le premier
    /// point pendant que le panneau annoncerait le deuxième.
    @Test func advancingTheRouteTargetChangesTheToken() {
        func token(_ target: MapRouteTarget?) -> TiledMapRepresentable.ContentToken {
            TiledMapRepresentable.ContentToken(
                game: .leonida,
                style: .neon,
                poisGeneration: 0,
                spotsGeneration: 0,
                myUnpublishedGeneration: 0,
                personalPinsGeneration: 0,
                showPersonalPins: true,
                draftPins: [],
                placement: nil,
                routeTarget: target,
                foundPOIIDs: [],
                canAdopt: false
            )
        }

        let first = MapRouteTarget(position: NormalizedPoint(x: 0.2, y: 0.5), category: .collectible)
        let next = MapRouteTarget(position: NormalizedPoint(x: 0.8, y: 0.5), category: .collectible)

        #expect(token(first) != token(next), "avancer d'une étape doit repousser le contenu")
        #expect(token(first) != token(nil), "quitter le mode doit retirer la pastille")
        #expect(token(first) == token(first), "rien n'a bougé : ne pas tout reconstruire")
    }
}
