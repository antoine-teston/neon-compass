import Testing
@testable import NeonCompass

/// La demande de carte qu'un autre onglet pose avant d'envoyer sur `MapScreen`.
///
/// Ce qu'elle répare, vu au simulateur le 2026-08-06 : `MapScreen.mapGame` naît
/// sur `.reference` (V) à chaque lancement et ne persiste rien, alors que
/// « Proposer un lieu » n'existe que sur VI. Les deux invitations à contribuer
/// enseignaient donc un geste puis envoyaient là où il ne mène nulle part —
/// systématiquement, pas par intermittence.
@MainActor
struct AppModelMapRequestTests {
    @Test func aucuneDemandeAuDepart() {
        #expect(AppModel().requestedMapGame == nil)
    }

    /// Les deux moitiés comptent : la carte VI ne sert à rien si l'onglet ne
    /// suit pas, et l'onglet seul est exactement le défaut qu'on corrige.
    @Test func contribuerDemandeLaCarteVIEtLOngletCarte() {
        let model = AppModel()
        model.openMapToContribute()
        #expect(model.requestedMapGame == .leonida)
        #expect(model.selectedTab == .map)
    }

    @Test func laDemandeSeConsommeUneSeuleFois() {
        let model = AppModel()
        model.openMapToContribute()
        #expect(model.consumeRequestedMapGame() == .leonida)
        #expect(model.consumeRequestedMapGame() == nil)
        #expect(model.requestedMapGame == nil)
    }

    /// Sans demande en cours, consommer ne doit rien inventer : `MapScreen`
    /// appelle avec `initial: true`, donc au montage, alors que personne n'a
    /// rien demandé. Rendre `.leonida` là forcerait la carte VI à chaque
    /// ouverture de l'onglet.
    @Test func consommerSansDemandeNeRendRien() {
        #expect(AppModel().consumeRequestedMapGame() == nil)
    }
}
