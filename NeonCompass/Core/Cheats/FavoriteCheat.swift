import Foundation
import SwiftData

/// Un favori : une triche, et rien d'autre.
///
/// **Le mode de saisie a fait partie de cette clé pendant une heure, et il en est
/// reparti.** Il y était pour un vrai défaut — cinq des trente-six codes de GTA V
/// n'ont pas d'équivalent manette, et un favori invisible consommait le plafond
/// sans qu'on puisse le retirer. Mais le but final est un widget d'activité qui
/// pose le code sur l'écran verrouillé, et deux choses s'y opposaient :
/// une sélection qui s'évapore quand on change de manette, et un plafond de
/// quarante qui obligerait à re-sélectionner ce que le widget doit montrer.
///
/// Le défaut est donc traité à l'affichage plutôt que dans la clé : un favori que
/// le mode actif ne sait pas saisir reste MONTRÉ, en le disant. Rien ne disparaît,
/// donc rien ne se consomme à vide.
///
/// Pas de contrainte d'unicité déclarée : `CheatsModel` cherche avant d'insérer,
/// et une contrainte qui change est la plus mauvaise des migrations SwiftData —
/// celle-ci en a déjà coûté une, échouée au lancement.
@Model
final class FavoriteCheat {
    var cheatID: String = ""

    init(cheatID: String) {
        self.cheatID = cheatID
    }
}
