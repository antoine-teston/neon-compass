import Foundation

/// Où s'intercalent les encarts publicitaires dans une colonne de cartes.
///
/// Extrait de `FeedModel`, où la règle vivait en statiques privées au fil, quand
/// l'écran Codes a eu besoin de la même. Un second exemplaire aurait divergé —
/// ce qui venait d'arriver à `MapGame`/`NewsGame` et au sélecteur de jeu.
enum InlineAdPlacement {
    /// Écart aléatoire entre deux encarts. Deux cartes au minimum : en dessous,
    /// la colonne devient une alternance publicité/contenu. Cinq au maximum :
    /// au-delà, une liste courte n'en porte plus aucun.
    static let gapRange = 2...5

    /// Jamais d'encart après la dernière carte : terminer une liste par une
    /// publicité, c'est ce qu'on voit dans les applications qu'on désinstalle.
    /// C'est la condition `< itemCount` qui le garantit, et non un cas
    /// particulier ajouté après coup.
    static func positions<G: RandomNumberGenerator>(
        itemCount: Int,
        using generator: inout G
    ) -> Set<Int> {
        var positions: Set<Int> = []
        var cardsBeforeNextAd = Int.random(in: gapRange, using: &generator)
        while cardsBeforeNextAd < itemCount {
            positions.insert(cardsBeforeNextAd - 1)
            cardsBeforeNextAd += Int.random(in: gapRange, using: &generator)
        }
        return positions
    }

    /// Variante déterministe, pour une liste qui se refiltre en continu.
    ///
    /// Le fil tire une fois et retient : ses entrées ne bougent qu'au
    /// rafraîchissement. La liste des codes, elle, se refiltre à chaque
    /// changement de mode de saisie, de jeu, de catégorie et à chaque frappe
    /// dans la recherche. Un tirage retenu demanderait de le refaire à cinq
    /// endroits — et un oubli déplacerait les encarts sans qu'on le voie ;
    /// un tirage non retenu les déplacerait à chaque rendu, donc sous le doigt
    /// pendant le défilement.
    ///
    /// Une graine tirée du nombre d'éléments affichés donne la stabilité sans
    /// l'état : même liste, mêmes positions, à chaque évaluation.
    static func positions(itemCount: Int) -> Set<Int> {
        var generator = SplitMix64(seed: UInt64(max(0, itemCount)))
        return positions(itemCount: itemCount, using: &generator)
    }
}

/// Générateur graine, reproductible d'un lancement à l'autre.
///
/// `SystemRandomNumberGenerator` ne l'est pas, et c'est bien ce qu'on veut pour
/// le fil. Ici il faut l'inverse : la même liste doit produire les mêmes
/// positions, sinon les encarts sautent à chaque rendu.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Décalage non nul : une graine de 0 doit produire une suite utilisable,
        // et une liste vide est un cas courant.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
