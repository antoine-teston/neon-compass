import SwiftUI

struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProgressRing(progress: model.overallProgress)
                    .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(POICategory.allCases, id: \.self) { category in
                        categoryRow(category)
                    }
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                trophySection
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func categoryRow(_ category: POICategory) -> some View {
        HStack {
            Text(category.localizedNameKey)
                .font(NCTypography.body)
                .foregroundStyle(.white)
            Spacer()
            Text("\(Int((model.progress(in: category) * 100).rounded()))%")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var trophySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("progress.trophies.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if model.trophies.isEmpty {
                Text("progress.trophies.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(model.trophies) { trophy in
                    trophyRow(trophy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trophyRow(_ trophy: Trophy) -> some View {
        Button {
            model.toggleTrophy(trophy)
        } label: {
            HStack {
                Image(systemName: model.isTrophyChecked(trophy) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isTrophyChecked(trophy) ? NCColor.neonCyan : .white.opacity(0.4))
                Text(trophy.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
