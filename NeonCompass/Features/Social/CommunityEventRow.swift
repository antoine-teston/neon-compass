import SwiftUI

struct CommunityEventRow: View {
    let event: CommunityEvent
    let communityName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.eventType.systemImage)
                .font(.body)
                .foregroundStyle(NCColor.neonCyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: communityName)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(event.eventType.localizationKey))
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                    if let date = event.startsAtDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer()
            Text(LocalizedStringKey(event.platform.localizationKey))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}
