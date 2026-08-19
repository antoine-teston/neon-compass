import Testing
@testable import NeonCompass

struct DiscoveryStateTests {
    private func text(_ value: String) -> LocalizedText {
        LocalizedText(en: value, fr: nil, es: nil, it: nil, de: nil)
    }

    private func challenge(
        id: String,
        game: Game,
        found: Int,
        expected: Int?,
        referenced: Int? = nil
    ) -> ChallengeProgress {
        ChallengeProgress(
            collection: POICollection(
                id: id, game: game, title: text(id), isChallenge: true, expectedCount: expected
            ),
            found: found,
            referenced: referenced ?? found
        )
    }

    // MARK: - Les deux jeux, toujours

    /// LE test de ce chantier côté Découverte. `gamesWithChallenges` filtrait les
    /// jeux sans défi, et les quinze collections publiées sont TOUTES celles de la
    /// carte de référence : le volet à venir n'apparaissait donc pas du tout dans
    /// l'écran censé montrer sa progression.
    @Test func bothGamesArePresentEvenWithNoChallengeAtAll() {
        let state = DiscoveryState(challenges: [], foundCountByGame: [:])
        #expect(state.games.map(\.game) == Game.allCases)
        #expect(state.challengeCount == 0)
    }

    /// L'ordre est celui de `GameSwitch` — le jeu à venir d'abord — et pas celui
    /// d'un dictionnaire, qui n'en a pas.
    @Test func theUpcomingGameComesFirst() {
        let state = DiscoveryState(challenges: [], foundCountByGame: [:])
        #expect(state.games.first?.game == .leonida)
        #expect(state.games.last?.game == .reference)
    }

    // MARK: - Un tiret, jamais zéro pour cent

    /// Zéro pour cent dirait « tu n'as rien trouvé » là où la vérité est « on ne
    /// sait pas encore combien il y en a ». C'est l'état prévu du volet à venir,
    /// dont personne ne connaîtra les totaux avant plusieurs semaines.
    @Test func anUnknownTotalGivesNoProgressAndNoExpectedCount() {
        let state = DiscoveryState(
            challenges: [challenge(id: "leo", game: .leonida, found: 4, expected: nil)],
            foundCountByGame: [.leonida: 12]
        )
        let upcoming = state.games.first { $0.game == .leonida }
        #expect(upcoming?.progress == nil)
        #expect(upcoming?.expectedCount == nil)
        // Le compte absolu, lui, reste juste et reste affiché.
        #expect(upcoming?.foundCount == 12)
    }

    @Test func aKnownTotalGivesBothTheFractionAndTheExpectedCount() {
        let state = DiscoveryState(
            challenges: [
                challenge(id: "a", game: .reference, found: 30, expected: 50),
                challenge(id: "b", game: .reference, found: 20, expected: 50),
            ],
            foundCountByGame: [.reference: 50]
        )
        let reference = state.games.first { $0.game == .reference }
        #expect(reference?.expectedCount == 100)
        #expect(reference?.foundInChallenges == 50)
        #expect(reference?.progress == 0.5)
    }

    /// Un défi sans total n'entre ni au numérateur ni au dénominateur : il ferait
    /// baisser le pourcentage d'un jeu dont on connaît par ailleurs des totaux.
    @Test func aTotallessChallengeDoesNotDiluteItsNeighbours() {
        let state = DiscoveryState(
            challenges: [
                challenge(id: "a", game: .reference, found: 25, expected: 50),
                challenge(id: "b", game: .reference, found: 7, expected: nil),
            ],
            foundCountByGame: [.reference: 32]
        )
        let reference = state.games.first { $0.game == .reference }
        #expect(reference?.expectedCount == 50)
        // 25 et non 32 : le défi sans total est hors des deux côtés de la
        // fraction, pas seulement du dénominateur.
        #expect(reference?.foundInChallenges == 25)
        #expect(reference?.progress == 0.5)
    }

    // MARK: - Le compte affiché EST le pourcentage de l'anneau

    /// Le défaut vu à l'écran sur iPad le 2026-08-19, et que rien ici n'attrapait :
    /// l'anneau annonçait 51 % pendant que le compte juste dessous disait
    /// « 204 / 267 », soit 76 %. Les deux nombres étaient justes séparément —
    /// 204 comptait TOUS les lieux cochés du jeu, 267 seulement les défis — et
    /// faux ensemble, posés de part et d'autre d'une barre de fraction.
    ///
    /// L'invariant : le quotient affiché est le pourcentage affiché.
    @Test func theDisplayedFractionIsExactlyTheRingsPercentage() {
        let state = DiscoveryState(
            challenges: [
                challenge(id: "a", game: .reference, found: 5, expected: 10),
                challenge(id: "b", game: .reference, found: 20, expected: 50),
                challenge(id: "sansTotal", game: .reference, found: 3, expected: nil),
            ],
            // Le compte d'exploration dépasse la somme des défis : c'est le cas
            // réel — un joueur coche aussi des lieux hors défi — et c'est lui qui
            // faisait mentir l'affichage.
            foundCountByGame: [.reference: 204]
        )
        let reference = state.games.first { $0.game == .reference }
        #expect(reference?.foundInChallenges == 25)
        #expect(reference?.expectedCount == 60)
        #expect(reference?.progress == 25.0 / 60.0)
        // Le compte d'exploration survit, il n'est simplement plus posé sur la
        // barre de fraction.
        #expect(reference?.foundCount == 204)
    }

    // MARK: - Le compte vient des POI, pas des défis

    /// Le corollaire du test `foundCountPerGameComesFromThePOIsNotTheChallenges`
    /// côté modèle : ici on vérifie que l'état PROPAGE ce compte au lieu de le
    /// recalculer sur les défis, ce qui rendrait zéro pour le volet à venir.
    @Test func theFoundCountIsTheOneHandedInNotOneDerivedFromChallenges() {
        let state = DiscoveryState(
            challenges: [challenge(id: "a", game: .reference, found: 1, expected: 3)],
            foundCountByGame: [.leonida: 9, .reference: 1]
        )
        #expect(state.games.first { $0.game == .leonida }?.foundCount == 9)
        #expect(state.games.first { $0.game == .reference }?.foundCount == 1)
    }

    @Test func aMissingCountIsZeroAndNotACrash() {
        let state = DiscoveryState(challenges: [], foundCountByGame: [.reference: 4])
        #expect(state.games.first { $0.game == .leonida }?.foundCount == 0)
    }

    // MARK: - Le décompte de défis

    /// C'est le nombre affiché sur le bouton qui ouvre la feuille, donc il compte
    /// les défis des DEUX jeux — la feuille les liste tous.
    @Test func theChallengeCountSpansBothGames() {
        let state = DiscoveryState(
            challenges: [
                challenge(id: "a", game: .reference, found: 0, expected: 5),
                challenge(id: "b", game: .reference, found: 0, expected: nil),
                challenge(id: "leo", game: .leonida, found: 0, expected: nil),
            ],
            foundCountByGame: [:]
        )
        #expect(state.challengeCount == 3)
    }
}
