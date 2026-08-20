import SwiftUI

/// L'en-tête d'une section de réglages : une pastille teintée, puis le titre.
///
/// L'idiome vient des Réglages iOS, et il sert ici la même chose : cinq sections
/// empilées dans un `Form` ne se distinguaient que par un titre en petites
/// capitales grises, donc il fallait LIRE pour retrouver « Apparence ». Une
/// couleur se repère sans lire.
///
/// Générique sur son fond et non `Color` : la section Pro porte le dégradé
/// `NCColor.sunset`, un `LinearGradient` — c'est la famille chaude qui dit « ce
/// qui se paie », et l'aplatir en une teinte unique romprait ce langage.
struct SettingsIconLabel<Tint: ShapeStyle>: View {
    private let titleKey: LocalizedStringKey
    private let systemImage: String
    private let tint: Tint

    init(_ titleKey: LocalizedStringKey, systemImage: String, tint: Tint) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            // Ni police ni couleur imposées : l'en-tête garde celles que le
            // `Form` donne aux sections sans pastille, sinon deux titres voisins
            // du même écran n'auraient ni la même taille ni la même teinte.
            // `textCase(nil)` en revanche est nécessaire — le style d'en-tête
            // passe son titre en capitales, ce qui le fait crier à côté d'une
            // pastille.
            Text(titleKey)
                .textCase(nil)
        } icon: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                // La pastille ne dit rien que le titre ne dise : VoiceOver n'a
                // pas à annoncer un glyphe en plus du mot qu'il illustre.
                .accessibilityHidden(true)
        }
    }
}
