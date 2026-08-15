import SwiftUI

/// Une carte par jeu pourvu d'événements, VI d'abord (l'ordre de
/// `availableGames`), glissement horizontal aligné page par page. Un seul jeu :
/// une seule carte, pas de points — la règle `showsGamePicker`, transposée.
struct WeeklyHeroPager: View {
    let model: OnlineEventsModel
    let now: Date
    var onOpenDetail: ((OnlineEvent) -> Void)? = nil

    @State private var pagedGame: Game?

    var body: some View {
        let games = model.availableGames
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(games) { game in
                        page(for: game)
                            .containerRelativeFrame(.horizontal)
                            .id(game)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $pagedGame)
            // La page visible EST la sélection : le reste de l'écran (bannière,
            // rappels) continue de raisonner sur `selectedGame`.
            .onChange(of: pagedGame) { _, game in
                if let game { model.selectedGame = game }
            }
            .onAppear { pagedGame = model.selectedGame }

            if games.count > 1 {
                dots(games)
            }
        }
    }

    @ViewBuilder
    private func page(for game: Game) -> some View {
        if let shown = model.currentEvent(at: now, game: game) ?? model.latestEvent(game: game) {
            WeeklyHeroCard(event: shown, now: now, onOpenDetail: onOpenDetail.map { open in { open(shown) } })
        }
    }

    private func dots(_ games: [Game]) -> some View {
        HStack(spacing: 6) {
            ForEach(games) { game in
                Circle()
                    .fill(game == pagedGame ? NCColor.neonCyan : .white.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
