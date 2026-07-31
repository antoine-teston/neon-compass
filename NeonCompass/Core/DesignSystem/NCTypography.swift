import SwiftUI

enum NCTypography {
    /// Titres d'écran uniquement — jamais le corps de texte.
    static let displayTitle = Font.system(size: 28, weight: .black, design: .rounded)

    /// Titre d'une carte dans une liste. Même famille arrondie que
    /// `displayTitle`, mais dimensionné pour qu'une carte reste une carte : le
    /// fil actu utilisait `displayTitle` pour chaque entrée, ce qui donnait des
    /// titres de trois lignes et une seule actu et demie par écran.
    static let cardTitle = Font.system(size: 17, weight: .bold, design: .rounded)

    /// Ligne d'informations d'une carte : catégorie, date. Assez petite pour
    /// s'effacer devant le titre, assez lisible pour être scannée.
    static let cardMeta = Font.system(size: 12, weight: .semibold, design: .rounded)

    static let body = Font.body
}
