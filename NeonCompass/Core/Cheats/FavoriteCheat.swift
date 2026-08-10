import Foundation
import SwiftData

/// Un favori, POUR UN MODE DE SAISIE donné.
///
/// **Pourquoi le mode fait partie de la clé.** Cinq des trente-six codes de GTA V
/// n'ont pas d'équivalent manette, un n'en a pas au clavier. Tant qu'un favori
/// valait pour tous les modes, mettre en favori cinq codes de téléphone puis
/// passer sur manette donnait une carte VIDE, un compteur à `5/5`, et tout ajout
/// refusé : le plafond se consommait sur des favoris qu'on ne pouvait plus voir.
/// Le mode dans la clé supprime ce cas au lieu de le rattraper.
///
/// L'unicité porte donc sur le COUPLE. Elle portait sur `cheatID` seul, ce qui
/// interdisait précisément ce qu'on veut : la même triche en favori sur deux
/// modes.
@Model
final class FavoriteCheat {
    #Unique<FavoriteCheat>([\.cheatID, \.inputMode])

    var cheatID: String

    /// Le `rawValue` de `CheatInputMode`, et non l'énumération : SwiftData stocke
    /// des types simples, et une chaîne survit à l'ajout d'un cas.
    ///
    /// **Vide = ligne d'avant la séparation par mode.** Le plafond n'existait pas
    /// et le mode non plus ; ces lignes sont adoptées au premier lancement par
    /// `CheatsModel`, qui leur attribue le mode mémorisé — celui sur lequel elles
    /// ont été posées. Aucune n'est supprimée.
    ///
    /// **La valeur par défaut n'est pas décorative : sans elle, l'app ne démarre
    /// plus.** Un attribut obligatoire ajouté à une entité qui existe déjà n'a
    /// rien à mettre dans les lignes déjà écrites, et la migration légère refuse
    /// — « Validation error missing attribute values on mandatory destination
    /// attribute ». Or `NeonCompassApp` construit son `ModelContainer` avec
    /// `try!` : ce n'est pas un mode dégradé, c'est un plantage au lancement pour
    /// quiconque avait un favori. Constaté à l'exécution, pas supposé.
    var inputMode: String = ""

    init(cheatID: String, inputMode: CheatInputMode) {
        self.cheatID = cheatID
        self.inputMode = inputMode.rawValue
    }
}

/// La clé d'un favori : une triche ET le mode de saisie sous lequel on l'a posée.
///
/// Un type plutôt qu'un tuple ou une chaîne concaténée : il se met dans un `Set`,
/// il se lit, et il empêche d'inverser les deux composantes par accident.
struct FavoriteKey: Hashable, Sendable {
    let cheatID: String
    let mode: CheatInputMode
}
