import Foundation
import Testing
@testable import NeonCompass

struct ContributionSubmissionErrorTests {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func leCodeFaitAutoriteSurLeStatut() {
        // Les DEUX 400 de `submit-contribution` ne se distinguent que par leur
        // code : c'est toute la raison pour laquelle le serveur en pose un.
        #expect(
            ContributionSubmissionError(status: 400, body: body(#"{"error":"x","code":"vocabulary"}"#))
                == .titleRejected
        )
        #expect(
            ContributionSubmissionError(status: 400, body: body(#"{"error":"x","code":"invalid"}"#))
                == .failed
        )
    }

    @Test func chaqueCodeTombeSurSonCas() {
        #expect(
            ContributionSubmissionError(status: 503, body: body(#"{"error":"x","code":"disabled"}"#))
                == .disabled
        )
        #expect(
            ContributionSubmissionError(status: 409, body: body(#"{"error":"x","code":"duplicate"}"#))
                == .duplicateNearby
        )
        #expect(
            ContributionSubmissionError(status: 429, body: body(#"{"error":"x","code":"cooldown","retryAfter":42}"#))
                == .cooldown(retryAfter: 42)
        )
    }

    @Test func unCooldownDeZeroNestPasUnCooldownInconnu() {
        // `0` est falsy dans le sérialiseur comme dans bien des lectures : s'il
        // se perdait, on afficherait une minute d'attente alors que le serveur
        // vient de dire qu'elle est écoulée.
        #expect(
            ContributionSubmissionError(status: 429, body: body(#"{"error":"x","code":"cooldown","retryAfter":0}"#))
                == .cooldown(retryAfter: 0)
        )
    }

    @Test func un429SansSecondesRetombeSurLaValeurDuServeur() {
        #expect(
            ContributionSubmissionError(status: 429, body: body(#"{"error":"x"}"#))
                == .cooldown(retryAfter: 60)
        )
    }

    @Test func leStatutSertDeRepliQuandLeCodeManque() {
        // Une fonction pas encore redéployée ne pose aucun code. Le chemin doit
        // rester intelligible plutôt que de tout écraser en « échec ».
        #expect(ContributionSubmissionError(status: 503, body: body(#"{"error":"x"}"#)) == .disabled)
        #expect(ContributionSubmissionError(status: 409, body: body(#"{"error":"x"}"#)) == .duplicateNearby)
        #expect(ContributionSubmissionError(status: 401, body: nil) == .signedOut)
    }

    @Test func un400SansCodeNaccusePasLeTitre() {
        // Sans code, on ne sait pas si c'est la forme ou le vocabulaire.
        // « Reformulez » serait un conseil faux une fois sur deux ; « réessayez »
        // ne l'est jamais tout à fait.
        #expect(ContributionSubmissionError(status: 400, body: body(#"{"error":"x"}"#)) == .failed)
    }

    @Test func unCorpsIllisibleOuAbsentRetombeSurEchec() {
        #expect(ContributionSubmissionError(status: 500, body: nil) == .failed)
        #expect(ContributionSubmissionError(status: 500, body: body("pas du json")) == .failed)
        #expect(ContributionSubmissionError(status: 0, body: nil) == .failed)
    }

    @Test func unCodeInconnuNeFaitPasEchouerLaLecture() {
        // Un code ajouté côté serveur avant que l'app ne le connaisse : il doit
        // se dégrader sur le statut, pas produire un cas absurde.
        #expect(
            ContributionSubmissionError(status: 409, body: body(#"{"error":"x","code":"quantum-flux"}"#))
                == .duplicateNearby
        )
    }
}
