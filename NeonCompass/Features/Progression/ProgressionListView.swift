import SwiftUI

struct ProgressionListView: View {
    @Bindable var model: ProgressionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                overviewCard
                trophyCard
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var overviewCard: some View {
        VStack(spacing: 20) {
            ProgressRing(progress: model.overallProgress)
                .frame(width: 140, height: 140)

            VStack(spacing: 14) {
                ForEach(POICategory.allCases, id: \.self) { category in
                    categoryRow(category)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func categoryRow(_ category: POICategory) -> some View {
        let percent = model.progress(in: category)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.localizedNameKey)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int((percent * 100).rounded()))%")
                    .font(NCTypography.body.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            ProgressView(value: percent)
                .tint(NCColor.neonCyan)
        }
    }

    private var trophyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("progress.trophies.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            if model.trophies.isEmpty {
                Text("progress.trophies.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.trophies.enumerated()), id: \.element.id) { index, trophy in
                        trophyRow(trophy)
                        if index < model.trophies.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
