import SwiftUI

extension View {
    /// Le halo d'enseigne.
    ///
    /// Deux ombres et non une : un seul rayon donne un flou plat, deux rayons
    /// donnent le cœur net et l'auréole large d'une enseigne au néon.
    ///
    /// Extrait d'`OnlineEventCountdown`, qui en était le seul porteur jusqu'à ce
    /// que le rebours de sortie ait besoin du même effet. Deux copies de ces
    /// deux lignes auraient divergé au premier réglage.
    func ncNeonGlow(_ color: Color) -> some View {
        shadow(color: color.opacity(0.9), radius: 4)
            .shadow(color: color.opacity(0.5), radius: 14)
    }
}
