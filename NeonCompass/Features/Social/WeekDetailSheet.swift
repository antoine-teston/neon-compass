import SwiftUI

/// La fiche complète de la semaine : l'`OnlineEventCard` d'avant, devenue le
/// détail du héro compact. Une feuille avec son propre `NavigationStack` —
/// aucun écran d'onglet n'a le sien.
struct WeekDetailSheet: View {
    let event: OnlineEvent
    let now: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NCColor.nightSky.ignoresSafeArea()
                ScrollView {
                    OnlineEventCard(event: event, now: now)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
            }
            .navigationTitle(Text(event.startsAt..<event.endsAt, format: .interval.day().month(.abbreviated)))
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
