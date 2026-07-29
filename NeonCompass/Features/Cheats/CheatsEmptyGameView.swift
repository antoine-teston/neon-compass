import SwiftUI

/// Ce que voit quelqu'un qui bascule sur un jeu dont aucun code n'existe
/// encore.
///
/// Le texte dit pourquoi c'est vide, pas seulement que c'est vide : les codes
/// viendront quand des joueurs les auront trouvés et confirmés, et nous ne les
/// devinerons pas d'avance. C'est la ligne que tient déjà le fil d'actu.
///
/// Informatif, sans bouton de notification : le seul dispositif d'abonnement de
/// l'app est câblé sur les catégories de POI, et le généraliser est un autre
/// chantier.
struct CheatsEmptyGameView: View {
    @Binding var game: Game

    var body: some View {
        VStack(spacing: 16) {
            // Le seul chemin de retour : la liste et sa barre de recherche, qui
            // portent d'ordinaire cette bascule, sont absentes de cet état.
            GameSwitch(game: $game)
                .padding(.bottom, 8)
            Image(systemName: "hourglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(NCColor.neonCyan)
            Text("cheats.empty.title")
                .font(NCTypography.cardTitle)
                .foregroundStyle(.white)
            Text("cheats.empty.body")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NCColor.nightSky.ignoresSafeArea())
    }
}
