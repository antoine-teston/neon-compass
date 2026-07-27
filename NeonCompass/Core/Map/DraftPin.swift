import Foundation

/// Pin d'un brouillon d'éditeur, rendu en contour pointillé pour se distinguer
/// d'un POI publié et d'un spot communautaire.
///
/// Ce type n'est délibérément PAS conditionné à `DEBUG`, contrairement au reste
/// de l'éditeur : `MapScrollView` le reçoit dans une liste qui, en Release, est
/// toujours vide. Le prix est un type inerte de six lignes ; le bénéfice est
/// zéro compilation conditionnelle dans le moteur de carte, qui est la pièce la
/// plus délicate du dépôt.
struct DraftPin: Identifiable, Equatable, Sendable {
    let id: String
    let position: NormalizedPoint
    let category: POICategory
}
