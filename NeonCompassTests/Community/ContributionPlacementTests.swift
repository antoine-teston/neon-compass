import Foundation
import Testing
@testable import NeonCompass

struct ContributionPlacementTests {
    private let origin = NormalizedPoint(x: 0.4, y: 0.6)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func placement(title: String = "Toit du parking") -> ContributionPlacement {
        var made = ContributionPlacement(position: origin)
        made.title = title
        return made
    }

    // MARK: - Le titre

    @Test func leTitreEstElague() {
        var made = placement(title: "  Toit du parking  ")
        #expect(made.trimmedTitle == "Toit du parking")
        #expect(made.canSubmit(now: now))

        made.title = "   "
        #expect(made.trimmedTitle.isEmpty)
        #expect(!made.canSubmit(now: now), "des espaces seuls ne sont pas un titre")
    }

    @Test func laBorneDe280PorteSurLeTitreElague() {
        var made = placement(title: String(repeating: "x", count: 280) + "   ")
        #expect(made.canSubmit(now: now))

        made.title = String(repeating: "x", count: 281)
        #expect(!made.canSubmit(now: now))
    }

    @Test func leCompteurNapparaitQuaLApproche() {
        var made = placement(title: String(repeating: "x", count: 239))
        #expect(!made.showsCounter, "un compteur permanent sur un champ que personne n'approche est du bruit")

        made.title = String(repeating: "x", count: 240)
        #expect(made.showsCounter)
    }

    // MARK: - Le refus ne jette rien

    @Test func unRefusConserveTitreEtCategorie() {
        var made = placement()
        made.category = .safehouse
        made.beganSending()
        made.failed(with: .duplicateNearby, now: now)

        // C'est l'argument décisif du panneau sur le bandeau fugace : il faut
        // POUVOIR réessayer, donc retrouver ce qu'on avait tapé.
        #expect(made.title == "Toit du parking")
        #expect(made.category == .safehouse)
        #expect(made.error == .duplicateNearby)
    }

    // MARK: - Le 409, et les deux gestes qui le lèvent

    @Test func deplacerEfface409() {
        var made = placement()
        made.failed(with: .duplicateNearby, now: now)

        made.position = NormalizedPoint(x: 0.7, y: 0.2)
        #expect(made.error == nil, "la déduplication est bornée à un rayon : déplacer lève le refus")
    }

    @Test func changerDeCategorieEfface409() {
        var made = placement()
        made.failed(with: .duplicateNearby, now: now)

        made.category = .vehicle
        #expect(made.error == nil, "la déduplication est bornée à une catégorie")
    }

    @Test func deplacerNeffacePasUnRefusQueLeDeplacementNeLevePas() {
        var made = placement()
        made.failed(with: .titleRejected, now: now)

        made.position = NormalizedPoint(x: 0.7, y: 0.2)
        #expect(made.error == .titleRejected, "bouger l'épingle ne rend pas le mot acceptable")
    }

    @Test func retaperLeTitreEfface400Vocabulaire() {
        var made = placement()
        made.failed(with: .titleRejected, now: now)

        made.title = "Toit du parking sur la marina"
        #expect(made.error == nil, "l'utilisateur fait exactement ce qu'on lui demande")
    }

    @Test func retaperLeTitreNeffacePas409() {
        var made = placement()
        made.failed(with: .duplicateNearby, now: now)

        made.title = "Un autre nom"
        #expect(made.error == .duplicateNearby, "renommer ne déplace pas l'épingle")
    }

    // MARK: - Le cooldown

    @Test func un429ArmeLecheanceEtDesarmeLenvoi() {
        var made = placement()
        made.failed(with: .cooldown(retryAfter: 42), now: now)

        #expect(made.remainingCooldown(now: now) == 42)
        #expect(!made.canSubmit(now: now))
    }

    @Test func lexpirationReamorceLenvoi() {
        var made = placement()
        made.failed(with: .cooldown(retryAfter: 42), now: now)

        #expect(!made.canSubmit(now: now.addingTimeInterval(41)))
        #expect(made.canSubmit(now: now.addingTimeInterval(42)))
        #expect(made.remainingCooldown(now: now.addingTimeInterval(42)) == nil)
    }

    @Test func leDecompteArrondiParExces() {
        var made = placement()
        made.failed(with: .cooldown(retryAfter: 42), now: now)

        // 41,5 s restantes doivent s'afficher « 42 », jamais « 41 » : annoncer
        // moins que l'attente réelle ferait échouer le renvoi.
        #expect(made.remainingCooldown(now: now.addingTimeInterval(0.5)) == 42)
    }

    @Test func leDernierEnvoiConnuLocalementArmeLecheanceDavance() {
        // Deux propositions d'affilée sur le même téléphone — le cas courant —
        // ne doivent jamais atteindre le réseau.
        let made = ContributionPlacement(position: origin, lastSubmissionAt: now.addingTimeInterval(-20))
        #expect(made.remainingCooldown(now: now) == 40)
        #expect(!made.canSubmit(now: now))
    }

    @Test func sansDernierEnvoiConnuRienNestArme() {
        let made = placement()
        #expect(made.remainingCooldown(now: now) == nil)
        #expect(made.canSubmit(now: now))
    }

    // MARK: - Les refus qui ne se réessaient pas

    @Test func leCoupeCircuitEtLaDeconnexionDesarmentLenvoi() {
        var made = placement()
        made.failed(with: .disabled, now: now)
        #expect(!made.canSubmit(now: now), "renvoyer contre un coupe-circuit fermé ne peut que rater")

        var other = placement()
        other.failed(with: .signedOut, now: now)
        #expect(!other.canSubmit(now: now), "il faut se reconnecter, pas réessayer")
    }

    @Test func unePanneSeReessaie() {
        var made = placement()
        made.failed(with: .failed, now: now)
        #expect(made.canSubmit(now: now))
    }

    // MARK: - Les phases

    @Test func lenvoiEnCoursDesarmeTout() {
        var made = placement()
        made.beganSending()
        #expect(!made.canSubmit(now: now), "sans ça, deux tapes rapides envoient deux fois")
        #expect(made.error == nil)
    }

    @Test func unSuccesPasseEnConfirmation() {
        var made = placement()
        made.beganSending()
        made.succeeded()
        #expect(made.phase == .confirmed)
        #expect(!made.canSubmit(now: now))
    }

    @Test func lerreurNestLueQuenSaisie() {
        var made = placement()
        made.failed(with: .duplicateNearby, now: now)
        made.beganSending()
        #expect(made.error == nil, "un refus périmé ne doit pas rester affiché pendant le renvoi")
    }
}
