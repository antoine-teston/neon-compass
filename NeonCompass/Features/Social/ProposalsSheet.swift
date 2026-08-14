import SwiftUI

/// La vue complète des propositions : l'actuel `ContributionsPanel`, rhabillé
/// en feuille avec son `NavigationStack` — sections « À découvrir » et « Les
/// mieux notées », bouton contribuer en bas, rien ne change dedans.
struct ProposalsSheet: View {
    let communityModel: CommunityModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    ContributionsPanel(communityModel: communityModel)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
            }
            .navigationTitle(Text("social.panel.proposals"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.event.detail.close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
