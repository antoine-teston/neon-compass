import SwiftUI

/// Les emplacements d'illustration de l'app.
///
/// Un cas par emplacement plutôt qu'une chaîne libre à l'appel, parce que
/// `UIImage(named:)` rend `nil` sur un nom mal orthographié — sans erreur, sans
/// avertissement, et l'écran se compose simplement sans son image. Énumérer les
/// emplacements permet à `NCArtworkTests` de parcourir `allCases` et d'affirmer
/// que chacun résout bien dans le catalogue. C'est la même leçon que les noms
/// d'icônes alternées, qui se perdaient de la même façon.
///
/// Les images vivent dans `Assets.xcassets/Artwork/`, en HEIC. Leur production
/// et leur étalonnage sont décrits dans
/// `docs/ops/2026-08-19-banque-images-prompts-et-themes-pro.md`.
enum NCArtwork: String, CaseIterable, Sendable {
    /// La bannière de l'écran de vente. Le seul écran où une image se paie
    /// littéralement — il doit convaincre, et il le faisait avec une liste à
    /// puces.
    case paywall = "artwork-paywall"

    /// L'écran d'avertissement, premier écran vu de l'app. C'est là que le ton
    /// se donne.
    case disclaimer = "artwork-disclaimer"

    var assetName: String { rawValue }
}

/// Une illustration d'emplacement, ou son repli.
///
/// **L'absence est un état normal, pas une erreur.** Les emplacements sont
/// câblés avant que les images définitives existent, et une image manquante
/// doit laisser l'écran se composer sans trou — c'est déjà le parti pris du
/// fond d'ambiance de `RootView`. Le repli permet à un écran qui avait déjà
/// quelque chose à cet endroit, comme le symbole de `DisclaimerView`, de le
/// garder tant que l'image n'est pas là.
///
/// Décorative par nature : `accessibilityHidden` est posé ici une fois pour
/// toutes plutôt que laissé à chaque appelant.
struct NCArtworkBanner<Fallback: View>: View {
    let artwork: NCArtwork
    var height: CGFloat = 160
    @ViewBuilder var fallback: Fallback

    var body: some View {
        if let image = UIImage(named: artwork.assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                // `clipped` avant `clipShape` : sans lui, `scaledToFill` laisse
                // l'image déborder du cadre et recouvrir ses voisines, le
                // masque arrondi ne rognant que les coins.
                .clipped()
                .clipShape(.rect(cornerRadius: 20))
                .accessibilityHidden(true)
        } else {
            fallback
        }
    }
}

extension NCArtworkBanner where Fallback == EmptyView {
    /// Sans repli : l'emplacement disparaît tant que l'image n'existe pas.
    init(artwork: NCArtwork, height: CGFloat = 160) {
        self.init(artwork: artwork, height: height) { EmptyView() }
    }
}
