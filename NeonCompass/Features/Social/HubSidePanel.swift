import SwiftUI

/// Le panneau latéral des vues complètes en largeur régulière — à la place
/// d'une feuille, la règle du projet pour l'iPad posé à côté de la télé.
struct HubSidePanel<Content: View>: View {
    let titleKey: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(titleKey)
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("social.event.detail.close"))
            }
            .padding(20)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
            ScrollView {
                content
                    .padding(20)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(NCColor.nightSky.opacity(0.96))
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
        }
        // Ombre bornée — la leçon « écran noir, app vivante ».
        .shadow(color: .black.opacity(0.3), radius: 18, x: -8, y: 0)
        .transition(.move(edge: .trailing))
    }
}
